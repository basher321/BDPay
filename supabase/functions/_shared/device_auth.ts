// Spec 08 signed device requests. Signed text: functionName + "\n" + X-Timestamp + "\n" + hex SHA-256 of the raw
// body. ECDSA P-256 / SHA-256, DER (Android) or raw. Checks run in the spec's order.

import {
  base64ToBytes,
  importP256Spki,
  sha256Hex,
  utf8,
  verifyP256,
} from "./crypto.ts";
import type { ErrorCode } from "./http.ts";
import type { Store } from "./store.ts";
import type { Device } from "./types.ts";

export const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;

export type DeviceAuth =
  | { ok: true; device: Device }
  | { ok: false; status: 401 | 403; code: ErrorCode };

const fail = (status: 401 | 403, code: ErrorCode): DeviceAuth => ({
  ok: false,
  status,
  code,
});

export async function checkDeviceRequest(
  functionName: string,
  headers: Headers,
  rawBody: Uint8Array<ArrayBuffer>,
  store: Pick<Store, "getDevice">,
  nowMs: number,
): Promise<DeviceAuth> {
  const deviceId = headers.get("X-Device-Id");
  const timestamp = headers.get("X-Timestamp");
  const signature = headers.get("X-Signature");
  if (!deviceId || !timestamp || !signature) {
    return fail(401, "missingSignature");
  }

  const device = await store.getDevice(deviceId);
  if (device === null) return fail(401, "unknownDevice");
  if (device.status === "revoked") return fail(403, "deviceRevoked");

  const ts = /^[0-9]{1,16}$/.test(timestamp) ? Number(timestamp) : NaN;
  if (!(Math.abs(nowMs - ts) <= MAX_CLOCK_SKEW_MS)) {
    return fail(401, "staleTimestamp");
  }

  const sig = base64ToBytes(signature);
  const key = await importP256Spki(device.publicKeySpki);
  if (sig === null || key === null) return fail(401, "badSignature");
  const text = `${functionName}\n${timestamp}\n${await sha256Hex(rawBody)}`;
  if (!(await verifyP256(key, sig, utf8(text)))) {
    return fail(401, "badSignature");
  }
  return { ok: true, device };
}
