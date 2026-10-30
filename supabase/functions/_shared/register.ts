// Spec 08 device-register: a merchant's phone registers its P-256 public key (Supabase user token).
// The server stores only the public key. Same merchant + installId -> key rotation / re-login.

import { importP256Spki } from "./crypto.ts";
import { type Deps, isObject, parseJson, readBody, replier } from "./http.ts";

export const FN = "device-register";
export const MAX_ACTIVE_DEVICES = 3;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface RegisterBody {
  installId: string;
  deviceName: string;
  publicKeySpki: string;
  appVersion: string;
  androidVersion: string;
}

const text = (v: unknown, max: number): v is string =>
  typeof v === "string" && v.trim() !== "" && [...v].length <= max;

function readRegisterBody(v: unknown): RegisterBody | null {
  if (!isObject(v)) return null;
  const { installId, deviceName, publicKeySpki, appVersion, androidVersion } =
    v;
  if (typeof installId !== "string" || !UUID.test(installId)) return null;
  if (typeof deviceName !== "string") return null;
  const name = deviceName.trim();
  const length = [...name].length; // characters, not UTF-16 units (Bangla names)
  if (length < 1 || length > 30) return null;
  if (typeof publicKeySpki !== "string" || publicKeySpki.length > 1024) {
    return null;
  }
  if (!text(appVersion, 50) || !text(androidVersion, 50)) return null;
  return {
    installId: installId.toLowerCase(),
    deviceName: name,
    publicKeySpki,
    appVersion: appVersion.trim(),
    androidVersion: androidVersion.trim(),
  };
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const reply = replier(FN, req, deps.log);
  if (req.method !== "POST") return reply.fail(405, "methodNotAllowed");

  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const user = token === "" ? null : await deps.users.verify(token);
  if (user === null) return reply.fail(401, "badUserToken");
  const owner = await deps.store.findMerchantForUser(user.userId);
  if (owner === null) return reply.fail(403, "noMerchant");
  const { merchantId } = owner;

  const raw = await readBody(req);
  if (raw === null) return reply.fail(413, "tooLarge", merchantId);
  const body = readRegisterBody(parseJson(raw));
  if (body === null) return reply.fail(400, "badRequest", merchantId);
  if ((await importP256Spki(body.publicKeySpki)) === null) {
    return reply.fail(400, "badPublicKey", merchantId);
  }

  const nowIso = new Date(deps.now()).toISOString();
  const existing = await deps.store.findDeviceByInstall(
    merchantId,
    body.installId,
  );
  let device;
  if (existing !== null) {
    device = await deps.store.updateDevice(existing.id, {
      name: body.deviceName,
      publicKeySpki: body.publicKeySpki,
      appVersion: body.appVersion,
      androidVersion: body.androidVersion,
      status: "active",
      lastSeenAt: nowIso,
    });
  } else {
    if (
      (await deps.store.countActiveDevices(merchantId)) >= MAX_ACTIVE_DEVICES
    ) {
      return reply.fail(409, "deviceLimit", merchantId);
    }
    device = await deps.store.createDevice({
      merchantId,
      name: body.deviceName,
      installId: body.installId,
      publicKeySpki: body.publicKeySpki,
      status: "active",
      appVersion: body.appVersion,
      androidVersion: body.androidVersion,
      lastSeenAt: nowIso,
    });
  }

  await deps.store.writeAudit({
    merchantId,
    actorType: "user",
    actorId: user.userId,
    action: "device.register",
    entity: "device",
    entityId: device.id,
    data: {
      installId: body.installId,
      name: body.deviceName,
      appVersion: body.appVersion,
      androidVersion: body.androidVersion,
      reRegistered: existing !== null,
    },
  });

  const rules = await deps.store.getParserRules();
  return reply.ok({
    deviceId: device.id,
    merchantId,
    serverTime: nowIso,
    rulesVersion: rules.version,
  }, merchantId);
}
