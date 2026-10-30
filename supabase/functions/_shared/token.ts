// Spec 09 pay tokens: 32 random bytes, base64url. Only SHA-256(token) is stored; the token itself never is.
// (Spec 10 later derives the token from PAY_TOKEN_SECRET and the session id; the hash rule stays.)

import { sha256Hex, utf8 } from "./crypto.ts";

/** 43 base64url characters (32 bytes, no padding). */
export const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export function base64Url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function newSessionToken(): string {
  return base64Url(crypto.getRandomValues(new Uint8Array(32)));
}

export function hashToken(token: string): Promise<string> {
  return sha256Hex(utf8(token));
}

export function isTokenShaped(token: unknown): token is string {
  return typeof token === "string" && TOKEN_PATTERN.test(token);
}
