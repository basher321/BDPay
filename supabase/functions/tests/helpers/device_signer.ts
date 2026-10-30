// Test helper: a phone's P-256 key and Android-style signed requests (plan section 4).
// Android's Signature("SHA256withECDSA") returns DER; Web Crypto returns raw r||s, so rawToDer converts it.

import { sha256Hex, utf8 } from "../../_shared/crypto.ts";

export interface DeviceKey {
  privateKey: CryptoKey;
  /** base64 SPKI, the same bytes as Android's publicKey.encoded. */
  publicKeySpki: string;
}

export function bytesToBase64(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

export async function newDeviceKey(): Promise<DeviceKey> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const spki = new Uint8Array(
    await crypto.subtle.exportKey("spki", pair.publicKey),
  );
  return { privateKey: pair.privateKey, publicKeySpki: bytesToBase64(spki) };
}

function derInt(x: Uint8Array): number[] {
  let i = 0;
  while (i < x.length - 1 && x[i] === 0) i++;
  const v = Array.from(x.subarray(i));
  if (v[0] & 0x80) v.unshift(0);
  return [0x02, v.length, ...v];
}

/** Raw r||s (64 bytes) -> DER SEQUENCE { INTEGER r, INTEGER s }, minimal, like Android. */
export function rawToDer(raw: Uint8Array): Uint8Array<ArrayBuffer> {
  const body = [...derInt(raw.subarray(0, 32)), ...derInt(raw.subarray(32))];
  return new Uint8Array([0x30, body.length, ...body]);
}

export async function signRaw(
  privateKey: CryptoKey,
  text: string,
): Promise<Uint8Array<ArrayBuffer>> {
  return new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      privateKey,
      utf8(text),
    ),
  );
}

export async function signedText(
  functionName: string,
  timestamp: string,
  body: Uint8Array<ArrayBuffer>,
): Promise<string> {
  return `${functionName}\n${timestamp}\n${await sha256Hex(body)}`;
}

export interface SignOptions {
  timestamp?: number;
  format?: "der" | "raw";
  /** Sign as if for another function (replay tests). */
  signAs?: string;
  /** Send this body instead of the signed one (tamper tests). */
  sendBody?: string;
  omit?: "X-Device-Id" | "X-Timestamp" | "X-Signature";
}

export async function signedRequest(
  functionName: string,
  deviceId: string,
  key: CryptoKey,
  body: string,
  opts: SignOptions = {},
): Promise<Request> {
  const ts = String(opts.timestamp ?? Date.now());
  const raw = await signRaw(
    key,
    await signedText(opts.signAs ?? functionName, ts, utf8(body)),
  );
  const sig = opts.format === "raw" ? raw : rawToDer(raw);
  const headers = new Headers({
    "content-type": "application/json",
    "X-Device-Id": deviceId,
    "X-Timestamp": ts,
    "X-Signature": bytesToBase64(sig),
  });
  if (opts.omit) headers.delete(opts.omit);
  return new Request(`http://localhost/${functionName}`, {
    method: "POST",
    headers,
    body: opts.sendBody ?? body,
  });
}
