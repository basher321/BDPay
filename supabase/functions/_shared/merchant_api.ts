// Spec 17 merchant-api: server-to-server API for websites on any platform (Bearer = BDPay API key).
//   POST .../merchant-api/checkouts {orderId, orderRef, amountPoisha, currency: "BDT", returnUrl}
//     -> {checkoutId, orderId, payUrl, status}; idempotent on (connection, orderId).
//   GET  .../merchant-api/checkouts/{orderId} -> {checkoutId, orderId, orderRef, amountPoisha, status}.
// Never logs the key, order ids, amounts or URLs. No CORS (the key must stay on the website's server).

import {
  API_KEY_PATTERN,
  cleanHttpsUrl,
  hashApiKey,
  orderPayToken,
} from "./connections.ts";
import { type Deps, isObject, parseJson, readBody, replier } from "./http.ts";
import { visibleStatus } from "./session_view.ts";
import { hashToken } from "./token.ts";
import type { PaymentSession } from "./types.ts";

export const FN = "merchant-api";
/** Spec 09: a session can be paid for 60 minutes. */
export const SUBMIT_WINDOW_MS = 60 * 60 * 1000;
export const RATE_LIMIT = 60; // per minute per connection
/** 1 crore taka in poisha; a guard against typos, not a business limit. */
export const MAX_AMOUNT_POISHA = 1_000_000_000;

// deno-lint-ignore no-control-regex
const CONTROL = /[\u0000-\u001f\u007f]/;

function cleanText(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  const n = [...t].length;
  return n >= 1 && n <= max && !CONTROL.test(t) ? t : null;
}

/** The part of the path after "merchant-api", e.g. ["checkouts", "A-1"]. */
function routeOf(req: Request): string[] | null {
  const parts = new URL(req.url).pathname.split("/").filter((p) => p !== "");
  const at = parts.indexOf(FN);
  if (at < 0) return null;
  try {
    return parts.slice(at + 1).map((p) => decodeURIComponent(p));
  } catch {
    return null;
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const reply = replier(FN, req, deps.log);
  const auth = req.headers.get("Authorization") ?? "";
  const key = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const conn = API_KEY_PATTERN.test(key)
    ? await deps.store.findConnectionByKeyHash(await hashApiKey(key))
    : null;
  if (conn === null || conn.kind !== "api" || conn.status !== "active") {
    return reply.fail(401, "badApiKey");
  }
  const merchantId = conn.merchantId;
  if (!(await deps.store.hitRateLimit(`api:${conn.id}`, RATE_LIMIT, 60))) {
    return reply.fail(429, "rateLimited", merchantId);
  }
  const secret = deps.config?.payTokenSecret;
  const payPageUrl = deps.config?.payPageUrl;
  if (!secret || !payPageUrl) {
    return reply.fail(503, "storeNotReady", merchantId);
  }

  const route = routeOf(req);
  if (route === null || route[0] !== "checkouts") {
    return reply.fail(404, "notFound", merchantId);
  }
  const now = deps.now();
  const status = (s: PaymentSession) => visibleStatus(s, now);

  if (req.method === "GET" && route.length === 2) {
    const orderId = cleanText(route[1], 100);
    const s = orderId === null
      ? null
      : await deps.store.findSessionByExternalOrder(conn.id, orderId);
    if (s === null) return reply.fail(404, "notFound", merchantId);
    return reply.ok({
      checkoutId: s.id,
      orderId: s.externalOrderId,
      orderRef: s.orderRef,
      amountPoisha: s.amountPoisha,
      status: status(s),
    }, merchantId);
  }
  if (req.method !== "POST" || route.length !== 1) {
    return reply.fail(405, "methodNotAllowed", merchantId);
  }

  const raw = await readBody(req, 8192);
  const body = raw === null ? undefined : parseJson(raw);
  if (!isObject(body)) return reply.fail(400, "badRequest", merchantId);
  const orderId = cleanText(body.orderId, 100);
  const orderRef = cleanText(body.orderRef, 40);
  const returnUrl = cleanHttpsUrl(body.returnUrl);
  if (orderId === null || orderRef === null) {
    return reply.fail(400, "badRequest", merchantId);
  }
  if (returnUrl === null) return reply.fail(400, "invalidUrl", merchantId);
  if (body.currency !== "BDT") {
    return reply.fail(400, "wrongCurrency", merchantId);
  }
  const amount = body.amountPoisha;
  if (
    typeof amount !== "number" || !Number.isSafeInteger(amount) ||
    amount <= 0 || amount > MAX_AMOUNT_POISHA
  ) {
    return reply.fail(400, "badAmount", merchantId);
  }

  const token = await orderPayToken(secret, conn.id, orderId);
  const payUrl = `${payPageUrl}?t=${token}`;
  const answer = (s: PaymentSession) =>
    s.amountPoisha !== amount
      ? reply.fail(409, "orderChanged", merchantId)
      : reply.ok({
        checkoutId: s.id,
        orderId,
        payUrl,
        status: status(s),
      }, merchantId);

  const existing = await deps.store.findSessionByExternalOrder(
    conn.id,
    orderId,
  );
  if (existing !== null) return answer(existing);

  let session: PaymentSession;
  try {
    session = await deps.store.createPaymentSession({
      merchantId,
      storeId: conn.id,
      tokenHash: await hashToken(token),
      orderRef,
      externalOrderId: orderId,
      amountPoisha: amount,
      returnUrl,
      submitDeadline: new Date(now + SUBMIT_WINDOW_MS).toISOString(),
    });
  } catch (e) {
    // A racing call for the same order made it first: answer with that one.
    const raced = await deps.store.findSessionByExternalOrder(conn.id, orderId);
    if (raced !== null) return answer(raced);
    throw e;
  }
  return answer(session);
}
