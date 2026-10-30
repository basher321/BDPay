// Spec 10: Shopify request checks. Every check fails closed: anything missing or odd is a "no".
// Signatures are checked with crypto.subtle.verify (constant-time by design). Nothing here logs.

const encoder = new TextEncoder();

async function hmacKey(secret: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

function hexToBytes(hex: string): Uint8Array<ArrayBuffer> | null {
  if (!/^[0-9a-f]{64}$/.test(hex)) return null;
  const out = new Uint8Array(32);
  for (let i = 0; i < 32; i++) {
    out[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function base64ToBytes(b64: string): Uint8Array<ArrayBuffer> | null {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(b64) || b64.length % 4 !== 0) return null;
  try {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

export function base64UrlToBytes(text: string): Uint8Array<ArrayBuffer> | null {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) return null;
  const b64 = text.replace(/-/g, "+").replace(/_/g, "/");
  return base64ToBytes(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
}

async function verifyHmac(
  secret: string,
  signature: Uint8Array<ArrayBuffer>,
  data: Uint8Array<ArrayBuffer>,
): Promise<boolean> {
  if (signature.length !== 32) return false;
  return await crypto.subtle.verify(
    "HMAC",
    await hmacKey(secret),
    signature,
    data,
  );
}

/** Shopify's escaping for the OAuth HMAC message. */
function escapePart(text: string, isKey: boolean): string {
  let t = text.replace(/%/g, "%25").replace(/&/g, "%26");
  if (isKey) t = t.replace(/=/g, "%3D");
  return t;
}

/**
 * OAuth callback query: drop "hmac" (and "signature"), sort the rest by key, join key=value with "&",
 * HMAC-SHA256 hex with the app secret. The received hmac must be 64 lower-case hex characters.
 * Duplicate keys are refused.
 */
export async function verifyOAuthQueryHmac(
  query: URLSearchParams,
  secret: string,
): Promise<boolean> {
  if (!secret) return false;
  const hmacValues = query.getAll("hmac");
  if (hmacValues.length !== 1) return false;
  const signature = hexToBytes(hmacValues[0]);
  if (!signature) return false;
  const seen = new Set<string>();
  const pairs: [string, string][] = [];
  for (const [key, value] of query) {
    if (key === "hmac" || key === "signature") continue;
    if (seen.has(key)) return false;
    seen.add(key);
    pairs.push([key, value]);
  }
  pairs.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  const message = pairs
    .map(([k, v]) => `${escapePart(k, true)}=${escapePart(v, false)}`)
    .join("&");
  return await verifyHmac(secret, signature, encoder.encode(message));
}

/** Webhook: base64(HMAC-SHA256(raw body bytes, secret)) in X-Shopify-Hmac-Sha256. Use the RAW body. */
export async function verifyWebhookHmac(
  rawBody: Uint8Array<ArrayBuffer>,
  header: string | null,
  secret: string,
): Promise<boolean> {
  if (!secret || !header) return false;
  const signature = base64ToBytes(header);
  if (!signature) return false;
  return await verifyHmac(secret, signature, rawBody);
}

export interface SessionTokenCheck {
  apiKey: string;
  secret: string;
  /** Milliseconds since epoch. */
  now: number;
}

const LEEWAY_SECONDS = 10;
const MAX_TOKEN_LENGTH = 4096;

function decodeJson(part: string): Record<string, unknown> | null {
  const bytes = base64UrlToBytes(part);
  if (!bytes) return null;
  try {
    const v = JSON.parse(new TextDecoder().decode(bytes));
    return v !== null && typeof v === "object" && !Array.isArray(v)
      ? v as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

/**
 * Shopify session token (JWT, HS256, signed with the app secret). Required: alg HS256, a valid signature,
 * aud = API key (string or an array containing it), exp and nbf (10 s leeway), dest = https://<shop>.myshopify.com.
 * If iss is present its host must equal dest's host. Returns the shop from dest, or null.
 */
export async function verifySessionToken(
  token: string,
  check: SessionTokenCheck,
): Promise<{ shop: string } | null> {
  if (!check.secret || !check.apiKey) return null;
  if (typeof token !== "string" || token.length > MAX_TOKEN_LENGTH) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const header = decodeJson(parts[0]);
  if (!header || header.alg !== "HS256") return null;
  if (header.typ !== undefined && header.typ !== "JWT") return null;
  const signature = base64UrlToBytes(parts[2]);
  if (!signature) return null;
  const signedPart = encoder.encode(`${parts[0]}.${parts[1]}`);
  if (!(await verifyHmac(check.secret, signature, signedPart))) return null;

  const claims = decodeJson(parts[1]);
  if (!claims) return null;
  const nowSec = check.now / 1000;
  const { aud, exp, nbf, dest, iss } = claims;
  const audOk = aud === check.apiKey ||
    (Array.isArray(aud) && aud.includes(check.apiKey));
  if (!audOk) return null;
  if (typeof exp !== "number" || exp <= nowSec - LEEWAY_SECONDS) return null;
  if (typeof nbf !== "number" || nbf > nowSec + LEEWAY_SECONDS) return null;
  const shop = shopFromUrl(dest);
  if (!shop) return null;
  if (iss !== undefined) {
    if (typeof iss !== "string") return null;
    let issHost: string;
    try {
      issHost = new URL(iss).hostname;
    } catch {
      return null;
    }
    if (issHost !== shop) return null;
  }
  return { shop };
}

function shopFromUrl(value: unknown): string | null {
  if (typeof value !== "string") return null;
  let u: URL;
  try {
    u = new URL(value);
  } catch {
    return null;
  }
  if (u.protocol !== "https:" || u.port !== "" || u.username || u.password) {
    return null;
  }
  return isValidShopDomain(u.hostname) ? u.hostname : null;
}

/** Compares two secrets without leaking content or length: both are hashed first, then compared fully. */
export async function constantTimeEqual(
  a: string,
  b: string,
): Promise<boolean> {
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(a)),
    crypto.subtle.digest("SHA-256", encoder.encode(b)),
  ]);
  const x = new Uint8Array(ha);
  const y = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

// Spec 05 shop-domain rules (ported from app/lib/core/validators.dart).
const SHOP = /^[a-z0-9][a-z0-9-]*\.myshopify\.com$/;

/** Trim, lower case, drop https:// or http://, drop any path, add ".myshopify.com" when there is no dot. */
export function normalizeShopDomain(input: string): string {
  let d = input.trim().toLowerCase();
  for (const scheme of ["https://", "http://"]) {
    if (d.startsWith(scheme)) d = d.slice(scheme.length);
  }
  const slash = d.indexOf("/");
  if (slash >= 0) d = d.slice(0, slash);
  if (!d.includes(".")) d = `${d}.myshopify.com`;
  return d;
}

export function isValidShopDomain(shop: string): boolean {
  return typeof shop === "string" && SHOP.test(shop);
}
