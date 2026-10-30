// Spec 08 device-deactivate (signed): the device revokes itself. A new device-register with the same installId
// makes it active again.

import { checkDeviceRequest } from "./device_auth.ts";
import { type Deps, isObject, parseJson, readBody, replier } from "./http.ts";

export const FN = "device-deactivate";

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const reply = replier(FN, req, deps.log);
  if (req.method !== "POST") return reply.fail(405, "methodNotAllowed");
  const raw = await readBody(req);
  if (raw === null) return reply.fail(413, "tooLarge");
  const auth = await checkDeviceRequest(
    FN,
    req.headers,
    raw,
    deps.store,
    deps.now(),
  );
  if (!auth.ok) return reply.fail(auth.status, auth.code);
  const { device } = auth;
  if (!isObject(parseJson(raw))) {
    return reply.fail(400, "badRequest", device.merchantId);
  }

  await deps.store.updateDevice(device.id, { status: "revoked" });
  await deps.store.writeAudit({
    merchantId: device.merchantId,
    actorType: "device",
    actorId: device.id,
    action: "device.deactivate",
    entity: "device",
    entityId: device.id,
    data: {},
  });
  return reply.ok({}, device.merchantId);
}
