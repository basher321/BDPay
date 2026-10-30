// Spec 08 crypto: SHA-256, base64, ECDSA P-256 verify, DER -> raw signatures. Web Crypto only; never throws on
// bad input (it returns null / false) and never logs.

const encoder = new TextEncoder();

export function utf8(text: string): Uint8Array<ArrayBuffer> {
  return encoder.encode(text);
}

/** Lower-case hex SHA-256 of bytes, or of a string's UTF-8 bytes. */
export async function sha256Hex(
  data: Uint8Array<ArrayBuffer> | string,
): Promise<string> {
  const bytes = typeof data === "string" ? utf8(data) : data;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Standard base64 (with or without padding) -> bytes; null when it is not base64. */
export function base64ToBytes(text: string): Uint8Array<ArrayBuffer> | null {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(text) || text.length % 4 === 1) {
    return null;
  }
  try {
    const bin = atob(text);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

/** One DER INTEGER as an unsigned 32-byte big-endian value; null when it is not a valid P-256 scalar. */
function derInteger(
  der: Uint8Array,
  at: number,
): { value: Uint8Array; next: number } | null {
  if (der[at] !== 0x02) return null;
  const len = der[at + 1];
  if (len === undefined || len === 0 || len > 33) return null;
  const start = at + 2;
  const end = start + len;
  if (end > der.length) return null;
  let bytes = der.subarray(start, end);
  if (bytes[0] & 0x80) return null; // negative
  if (bytes.length > 1 && bytes[0] === 0 && !(bytes[1] & 0x80)) {
    return null; // not minimal
  }
  if (bytes[0] === 0 && bytes.length > 1) bytes = bytes.subarray(1);
  if (bytes.length > 32) return null;
  if (bytes.every((b) => b === 0)) return null; // zero
  const value = new Uint8Array(32);
  value.set(bytes, 32 - bytes.length);
  return { value, next: end };
}

/** Strict DER ECDSA signature (SEQUENCE of two INTEGERs) -> raw r||s, 64 bytes; null when not valid DER. */
export function derToRaw(der: Uint8Array): Uint8Array<ArrayBuffer> | null {
  if (der.length < 8 || der[0] !== 0x30) return null;
  const len = der[1];
  if (len >= 0x80 || len !== der.length - 2) return null; // P-256 always uses the short length form
  const r = derInteger(der, 2);
  if (r === null) return null;
  const s = derInteger(der, r.next);
  if (s === null || s.next !== der.length) return null;
  const raw = new Uint8Array(64);
  raw.set(r.value, 0);
  raw.set(s.value, 32);
  return raw;
}

/** DER first (Android's format); else 64 raw bytes as they are; else null (plan D78). */
export function signatureToRaw(
  sig: Uint8Array,
): Uint8Array<ArrayBuffer> | null {
  const raw = derToRaw(sig);
  if (raw !== null) return raw;
  return sig.length === 64 ? new Uint8Array(sig) : null;
}

/** Imports a base64 SPKI as a P-256 verify key; null when it is not a P-256 public key. */
export async function importP256Spki(
  spkiBase64: string,
): Promise<CryptoKey | null> {
  const spki = base64ToBytes(spkiBase64);
  if (spki === null || spki.length === 0) return null;
  try {
    return await crypto.subtle.importKey(
      "spki",
      spki,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
  } catch {
    return null;
  }
}

/** ECDSA P-256 / SHA-256 verify of a DER or raw signature. */
export async function verifyP256(
  key: CryptoKey,
  signature: Uint8Array,
  data: Uint8Array<ArrayBuffer>,
): Promise<boolean> {
  const raw = signatureToRaw(signature);
  if (raw === null) return false;
  try {
    return await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      raw,
      data,
    );
  } catch {
    return false;
  }
}
