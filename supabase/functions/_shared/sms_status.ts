// Spec 09 sms-status (signed device request, same check as spec 08): the phone asks for the latest result of its
// SMS. POST {smsIds: [1..100]} -> {ok: true, results: [{smsId, verifyStatus, serverMessage, claim}]}.
// Ids of another merchant are left out.

import { checkDeviceRequest } from "./device_auth.ts";
import { type Deps, isObject, parseJson, readBody, replier } from "./http.ts";
import { REJECT_MESSAGES } from "./ingest.ts";
import { smsOutcome } from "./matcher.ts";

export const FN = "sms-status";
export const MAX_IDS = 100;

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
  const merchantId = auth.device.merchantId;
  const body = parseJson(raw);
  const ids = isObject(body) ? body.smsIds : undefined;
  if (
    !Array.isArray(ids) || ids.length < 1 || ids.length > MAX_IDS ||
    !ids.every((x) => typeof x === "string" && x.length <= 64)
  ) {
    return reply.fail(400, "badRequest", merchantId);
  }
  const rows = await deps.store.getSmsResults(merchantId, [
    ...new Set(ids as string[]),
  ]);
  const results = rows.map((r) => {
    const outcome = smsOutcome(r);
    const serverMessage =
      r.sms.status === "rejected" && r.sms.rejectReason !== null
        ? REJECT_MESSAGES[r.sms.rejectReason]
        : outcome.serverMessage;
    return {
      smsId: r.sms.id,
      verifyStatus: outcome.verifyStatus,
      serverMessage,
      claim: r.claim === null || r.session === null ? null : {
        claimId: r.claim.id,
        orderRef: r.session.orderRef,
        expectedAmountPoisha: r.session.amountPoisha,
      },
    };
  });
  return reply.ok({ results }, merchantId);
}
