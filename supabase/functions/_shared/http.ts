// Spec 08 HTTP helpers: JSON responses, fixed error texts, a capped body reader and the safe top-level wrapper.
// Error messages are fixed per code and never built from the request, so no input can be echoed or logged.

import type { Matcher } from "./matcher.ts";
import type { OrderNotifier } from "./notifier.ts";
import type { RateLimiter } from "./rate_limit.ts";
import type { Store } from "./store.ts";
import type { UserVerifier } from "./user_auth.ts";

export const MAX_BODY_BYTES = 256 * 1024;

export type ErrorCode =
  | "methodNotAllowed"
  | "badRequest"
  | "tooLarge"
  | "missingSignature"
  | "unknownDevice"
  | "deviceRevoked"
  | "staleTimestamp"
  | "badSignature"
  | "badUserToken"
  | "noMerchant"
  | "deviceLimit"
  | "badPublicKey"
  | "storeNotReady"
  | "rateLimited"
  | "notFound"
  | "badCronSecret"
  | "internalError";

const MESSAGES: Record<ErrorCode, string> = {
  methodNotAllowed: "Only POST is allowed.",
  badRequest: "The request body is not valid.",
  tooLarge: "The request body is too large.",
  missingSignature: "The device signature headers are missing.",
  unknownDevice: "This device is not registered.",
  deviceRevoked: "This device has been deactivated.",
  staleTimestamp: "The request time is too far from the server time.",
  badSignature: "The device signature is not valid.",
  badUserToken: "The user token is not valid.",
  noMerchant: "This user does not own a merchant.",
  deviceLimit: "The merchant already has the most active devices allowed.",
  badPublicKey: "The public key is not a P-256 key.",
  storeNotReady: "The data store is not ready.",
  rateLimited: "Too many requests. Try again later.",
  notFound: "Not found.",
  badCronSecret: "The cron secret is missing or wrong.",
  internalError: "Something went wrong on the server.",
};

/** One log line. Only these fields exist, so nothing else can be logged (spec 08 non-functional rules). */
export interface LogEntry {
  fn: string;
  requestId: string;
  code: string;
  merchantId: string | null;
}
export type Logger = (entry: LogEntry) => void;

export const consoleLogger: Logger = (entry) =>
  console.log(JSON.stringify(entry));

/** Spec 15: LATEST_APP_VERSION and APP_DOWNLOAD_URL, checked (heartbeat.ts releaseFromEnv). */
export interface AppRelease {
  latestAppVersion: string;
  appDownloadUrl: string;
}

/** Spec 09: environment settings, read once in depsFromEnv. Empty or unset values fail closed. */
export interface AppConfig {
  payPageOrigin?: string;
  cronSecret?: string;
  rateLimitPepper?: string;
}

/** What every core handler gets. now() is milliseconds since epoch. */
export interface Deps {
  store: Store;
  users: UserVerifier;
  matcher: Matcher;
  now: () => number;
  log: Logger;
  /** Spec 09 / 15 rate limiter (health); absent until the real one exists. */
  limiter?: RateLimiter;
  /** Spec 15: the newest app for the update notice (device-heartbeat); absent when not configured. */
  release?: AppRelease;
  /** Spec 09: told after a payment is verified (spec 10 plugs in Shopify). Absent = do nothing. */
  notifier?: OrderNotifier;
  /** Spec 09 settings from the environment (read only in depsFromEnv). */
  config?: AppConfig;
}

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export function error(status: number, code: ErrorCode): Response {
  return json(status, { ok: false, error: code, message: MESSAGES[code] });
}

/** The platform's request id when it looks like one, else a new UUID. Never logs header text as is. */
export function requestIdOf(req: Request): string {
  const id = req.headers.get("sb-request-id") ??
    req.headers.get("x-request-id");
  return id !== null && /^[A-Za-z0-9-]{1,64}$/.test(id)
    ? id
    : crypto.randomUUID();
}

/** Reads at most maxBytes; null when the body is longer (Content-Length is not trusted). */
export async function readBody(
  req: Request,
  maxBytes = MAX_BODY_BYTES,
): Promise<Uint8Array<ArrayBuffer> | null> {
  if (req.body === null) return new Uint8Array(0);
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const out = new Uint8Array(size);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.byteLength;
  }
  return out;
}

/** Parses UTF-8 JSON; undefined when it is not valid. The parse error (which quotes the body) is dropped. */
export function parseJson(bytes: Uint8Array): unknown {
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return undefined;
  }
}

export function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** Builds responses and writes the one log line per request. */
export function replier(fn: string, req: Request, log: Logger) {
  const requestId = requestIdOf(req);
  return {
    ok(body: Record<string, unknown>, merchantId: string | null): Response {
      log({ fn, requestId, code: "ok", merchantId });
      return json(200, { ok: true, ...body });
    },
    fail(
      status: number,
      code: ErrorCode,
      merchantId: string | null = null,
    ): Response {
      log({ fn, requestId, code, merchantId });
      return error(status, code);
    },
  };
}

export type Handler = (req: Request, deps: Deps) => Promise<Response>;

/**
 * The top-level wrapper used by every index.ts. No deps (no store yet) -> 503 storeNotReady. Anything thrown
 * -> 500 internalError; the error object is never logged (its message or stack could hold request data).
 */
export function serveFunction(
  fn: string,
  handle: Handler,
  getDeps: () => Deps | null,
  log: Logger = consoleLogger,
): (req: Request) => Promise<Response> {
  return async (req) => {
    try {
      const deps = getDeps();
      if (deps === null) {
        return replier(fn, req, log).fail(503, "storeNotReady");
      }
      return await handle(req, deps);
    } catch {
      return replier(fn, req, log).fail(500, "internalError");
    }
  };
}
