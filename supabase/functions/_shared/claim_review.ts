// Spec 09 claim-review: the merchant approves or rejects a mismatch (Supabase user token; the user must own the
// claim's merchant). POST {smsId, decision: approve | reject, note?} -> {ok: true, result: done | notAllowed | notFound}.

import { type Deps, isObject, parseJson, readBody, replier } from "./http.ts";
import { NoopNotifier, notifySafely } from "./notifier.ts";

export const FN = "claim-review";

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const reply = replier(FN, req, deps.log);
  if (req.method !== "POST") return reply.fail(405, "methodNotAllowed");
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const user = token === "" ? null : await deps.users.verify(token);
  if (user === null) return reply.fail(401, "badUserToken");
  const owner = await deps.store.findMerchantForUser(user.userId);
  if (owner === null) return reply.fail(403, "noMerchant");
  const merchantId = owner.merchantId;

  const raw = await readBody(req, 4096);
  const body = raw === null ? undefined : parseJson(raw);
  const note = isObject(body) && typeof body.note === "string"
    ? body.note.trim()
    : "";
  if (
    !isObject(body) || typeof body.smsId !== "string" ||
    (body.decision !== "approve" && body.decision !== "reject") ||
    (body.note !== undefined && typeof body.note !== "string") ||
    note.length > 200
  ) {
    return reply.fail(400, "badRequest", merchantId);
  }

  const claim = await deps.store.findMismatchClaimBySms(body.smsId);
  if (claim === null || claim.merchantId !== merchantId) {
    const sms = await deps.store.getSms(body.smsId);
    const own = sms !== null && sms.merchantId === merchantId;
    return reply.ok({ result: own ? "notAllowed" : "notFound" }, merchantId);
  }

  const noteOrNull = note === "" ? null : note;
  const outcome = body.decision === "approve"
    ? await deps.store.recordVerified({
      claimId: claim.id,
      smsId: body.smsId,
      method: "manual",
      userId: user.userId,
      note: noteOrNull,
    })
    : await deps.store.recordRejected({
      claimId: claim.id,
      userId: user.userId,
      note: noteOrNull,
    });
  if (outcome === "conflict") {
    return reply.ok({ result: "notAllowed" }, merchantId);
  }

  await deps.store.writeAudit({
    merchantId,
    actorType: "user",
    actorId: user.userId,
    action: body.decision === "approve" ? "claim.approve" : "claim.reject",
    entity: "claim",
    entityId: claim.id,
    data: {
      from: "mismatch",
      to: body.decision === "approve" ? "verified" : "rejected",
      note: noteOrNull,
    },
  });
  if (body.decision === "approve") {
    const session = await deps.store.getSession(claim.sessionId);
    if (session !== null) {
      await notifySafely(
        deps.notifier ?? new NoopNotifier(),
        session,
        deps.log,
        FN,
        "claim-review",
      );
    }
  }
  return reply.ok({ result: "done" }, merchantId);
}
