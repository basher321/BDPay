// Spec 13a parser-rules (signed): the phone downloads the active SMS rules when the heartbeat reports a higher
// rulesVersion. Same signed check as spec 08. Logs only the fixed entry (fn, requestId, code, merchantId).

import { checkDeviceRequest } from "./device_auth.ts";
import { type Deps, isObject, parseJson, readBody, replier } from "./http.ts";

export const FN = "parser-rules";

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
  const active = await deps.store.getParserRules();
  return reply.ok(
    { version: active.version, rules: active.rules },
    device.merchantId,
  );
}
