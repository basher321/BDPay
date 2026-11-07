// Spec 17 shared rules for store connections: validation, API keys, derived secrets and the public JSON shape.
// Keys and secrets are never logged or stored in plain form (only SHA-256 of the API key and its first 12 chars).

import { sha256Hex, utf8 } from "./crypto.ts";
import { base64Url } from "./token.ts";
import type { ConnectionRecord, Platform, StoreConnection } from "./types.ts";
import { PLATFORMS } from "./types.ts";

export const API_KEY_PREFIX = "bdp_live_";
/** "bdp_live_" + 43 base64url characters. */
export const API_KEY_PATTERN = /^bdp_live_[A-Za-z0-9_-]{43}$/;
export const KEY_PREFIX_LENGTH = 12;

export function isPlatform(v: unknown): v is Platform {
  return typeof v === "string" && (PLATFORMS as readonly string[]).includes(v);
}

/** 2 to 60 characters after trimming, no control characters. */
export function cleanSiteName(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  const n = [...t].length;
  // deno-lint-ignore no-control-regex
  if (n < 2 || n > 60 || /[\u0000-\u001f\u007f]/.test(t)) return null;
  return t;
}

/**
 * An https URL with a real host name: no user info, no IP literal, not localhost, at most 300 characters.
 * Returns the normalized form (no fragment; a trailing "/" removed from a bare host) or null.
 */
export function cleanHttpsUrl(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  if (t.length === 0 || t.length > 300) return null;
  let u: URL;
  try {
    u = new URL(t);
  } catch {
    return null;
  }
  const host = u.hostname.toLowerCase();
  if (
    u.protocol !== "https:" || u.username !== "" || u.password !== "" ||
    !host.includes(".") || host === "localhost" ||
    host.endsWith(".localhost") ||
    /^[0-9.]+$/.test(host) || host.startsWith("[")
  ) {
    return null;
  }
  u.hash = "";
  const out = u.toString();
  return u.pathname === "/" && u.search === "" ? out.replace(/\/$/, "") : out;
}

export function newApiKey(): string {
  return API_KEY_PREFIX + base64Url(crypto.getRandomValues(new Uint8Array(32)));
}

export function hashApiKey(key: string): Promise<string> {
  return sha256Hex(utf8(key));
}

export function keyPrefixOf(key: string): string {
  return key.slice(0, KEY_PREFIX_LENGTH);
}

async function hmac(secret: string, data: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    utf8(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, utf8(data)));
}

export async function hmacHex(secret: string, data: string): Promise<string> {
  return Array.from(
    await hmac(secret, data),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}

/** The pay token of an API order: the same connection + orderId always gives the same token (43 chars). */
export async function orderPayToken(
  secret: string,
  storeId: string,
  orderId: string,
): Promise<string> {
  return base64Url(await hmac(secret, `api-order:${storeId}:${orderId}`));
}

/** The webhook signing secret of a connection; recomputed when needed, never stored. */
export async function webhookSecret(
  secret: string,
  connectionId: string,
  version: number,
): Promise<string> {
  return "whsec_" +
    base64Url(await hmac(secret, `webhook:${connectionId}:${version}`));
}

/** The JSON the app gets: never the key hash or any secret. */
export function publicConnection(c: ConnectionRecord): StoreConnection {
  return {
    id: c.id,
    merchantId: c.merchantId,
    platform: c.platform,
    kind: c.kind,
    siteName: c.siteName,
    siteUrl: c.siteUrl,
    webhookUrl: c.webhookUrl,
    apiKeyPrefix: c.apiKeyPrefix,
    status: c.status,
    lastError: c.lastError,
    connectedAt: c.connectedAt,
  };
}
