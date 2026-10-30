// Spec 09 claim-review, sms-status and claims-expire, plus the TrxID rules matching the pay page.
import assert from "node:assert/strict";
import { handle as claimReview } from "../_shared/claim_review.ts";
import {
  cronAllowed,
  handle as claimsExpire,
} from "../_shared/claims_expire.ts";
import { handle as paySession } from "../_shared/pay_session.ts";
import { handle as smsStatus } from "../_shared/sms_status.ts";
import {
  isValidTrxId as edgeValid,
  normalizeTrxId as edgeNorm,
} from "../_shared/trx_format.ts";
import {
  isValidTrxId as pageValid,
  normalizeTrxId as pageNorm,
} from "../../../pay_page/logic.js";
import { signedRequest } from "./helpers/device_signer.ts";
import {
  addSms,
  CRON,
  newSession,
  payWorld,
  postReq,
} from "./helpers/pay_world.ts";
import { MIN, USER_TOKEN } from "./helpers/world.ts";

type W = Awaited<ReturnType<typeof payWorld>>;

/** A mismatch: order 45000, SMS 43000. */
async function mismatchFlow(w: W) {
  const { token, session } = await newSession(w, { amountPoisha: 45000 });
  const sms = await addSms(w, "MISM1234", { amountPoisha: 43000 });
  await paySession(postReq(token, "bkash", "MISM1234"), w.deps);
  return { token, session, sms };
}

const review = (
  w: W,
  smsId: string,
  decision: string,
  token = USER_TOKEN,
  note?: string,
) =>
  claimReview(
    new Request("http://localhost/claim-review", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        smsId,
        decision,
        ...(note === undefined ? {} : { note }),
      }),
    }),
    w.deps,
  );

Deno.test("claim-review: approve -> done, verified (manual), audited, notifier told", async () => {
  const w = await payWorld();
  const { session, sms } = await mismatchFlow(w);
  const res = await review(
    w,
    sms.id,
    "approve",
    USER_TOKEN,
    "customer paid the rest in cash",
  );
  assert.deepEqual(await res.json(), { ok: true, result: "done" });
  assert.equal(w.store.sessions.get(session.id)!.status, "verified");
  assert.equal(w.store.matches[0].method, "manual");
  const audit = w.store.audit.at(-1)!;
  assert.equal(audit.action, "claim.approve");
  assert.equal(audit.data.from, "mismatch");
  assert.equal(audit.data.to, "verified");
  assert.deepEqual(w.notifier.verified, [session.id]);
});

Deno.test("claim-review: reject -> done, session rejected; a second decision -> notAllowed", async () => {
  const w = await payWorld();
  const { session, sms } = await mismatchFlow(w);
  assert.equal(
    (await (await review(w, sms.id, "reject")).json()).result,
    "done",
  );
  assert.equal(w.store.sessions.get(session.id)!.status, "rejected");
  assert.equal(w.store.audit.at(-1)!.action, "claim.reject");
  assert.equal(
    (await (await review(w, sms.id, "approve")).json()).result,
    "notAllowed",
  );
});

Deno.test("claim-review: not a mismatch -> notAllowed; another merchant's SMS or unknown -> notFound; bad token 401", async () => {
  const w = await payWorld();
  const own = await addSms(w, "OWNS1234");
  assert.equal(
    (await (await review(w, own.id, "approve")).json()).result,
    "notAllowed",
  );
  const theirs = await addSms(w, "THEI1234", { merchantId: "m2" });
  assert.equal(
    (await (await review(w, theirs.id, "approve", "token-owner-m2")).json())
      .result,
    "notAllowed",
  );
  assert.equal(
    (await (await review(w, theirs.id, "approve")).json()).result,
    "notFound",
  );
  assert.equal(
    (await (await review(w, crypto.randomUUID(), "approve")).json()).result,
    "notFound",
  );
  assert.equal((await review(w, own.id, "approve", "wrong-token")).status, 401);
  assert.equal((await review(w, own.id, "maybe")).status, 400);
});

const status = async (w: W, ids: string[]) => {
  const res = await smsStatus(
    await signedRequest(
      "sms-status",
      w.device.id,
      w.key.privateKey,
      JSON.stringify({ smsIds: ids }),
      {
        timestamp: w.clock.now,
      },
    ),
    w.deps,
  );
  return { code: res.status, body: await res.json() };
};

Deno.test("sms-status: verified, mismatch with claim info, rejected by merchant, pending; other merchants left out", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  const paid = await addSms(w, "PAID1234");
  await paySession(postReq(token, "bkash", "PAID1234"), w.deps);
  const { session: ms, sms: mismatch } = await mismatchFlow(w);
  const waiting = await addSms(w, "WAIT1234");
  const other = await addSms(w, "OTHR1234", { merchantId: "m2" });
  const r = await status(w, [paid.id, mismatch.id, waiting.id, other.id]);
  assert.equal(r.code, 200);
  const by = Object.fromEntries(
    r.body.results.map((x: { smsId: string }) => [x.smsId, x]),
  );
  assert.equal(Object.keys(by).length, 3);
  assert.equal(by[paid.id].verifyStatus, "verified");
  assert.equal(by[paid.id].serverMessage, "অর্ডারের সাথে মিলেছে");
  assert.equal(by[mismatch.id].verifyStatus, "mismatch");
  assert.deepEqual(by[mismatch.id].claim, {
    claimId: ms.activeClaimId ?? w.store.sessions.get(ms.id)!.activeClaimId,
    orderRef: "#1045",
    expectedAmountPoisha: 45000,
  });
  assert.equal(by[waiting.id].verifyStatus, "pending");
  assert.equal(by[waiting.id].claim, null);
  await review(w, mismatch.id, "reject");
  const after = await status(w, [mismatch.id]);
  assert.equal(after.body.results[0].verifyStatus, "rejected");
  assert.equal(after.body.results[0].serverMessage, "ম্যানুয়ালি বাতিল");
});

Deno.test("sms-status: manual approval message; 0 or 101 ids -> 400; unsigned -> 401", async () => {
  const w = await payWorld();
  const { sms } = await mismatchFlow(w);
  await review(w, sms.id, "approve");
  assert.equal(
    (await status(w, [sms.id])).body.results[0].serverMessage,
    "ম্যানুয়ালি অনুমোদিত",
  );
  assert.equal((await status(w, [])).code, 400);
  assert.equal(
    (await status(w, Array.from({ length: 101 }, (_, i) => `id-${i}`))).code,
    400,
  );
  const unsigned = await smsStatus(
    new Request("http://localhost/sms-status", { method: "POST", body: "{}" }),
    w.deps,
  );
  assert.equal(unsigned.status, 401);
});

const expire = (w: W, secret?: string) =>
  claimsExpire(
    new Request("http://localhost/claims-expire", {
      method: "POST",
      headers: secret === undefined ? {} : { "X-Cron-Secret": secret },
      body: "{}",
    }),
    w.deps,
  );

Deno.test("claims-expire: wrong or missing secret -> 401; an empty configured secret refuses everything", async () => {
  const w = await payWorld();
  assert.equal((await expire(w)).status, 401);
  assert.equal((await expire(w, "nope")).status, 401);
  w.deps.config = { ...w.deps.config, cronSecret: "" };
  assert.equal((await expire(w, "")).status, 401);
  assert.equal(
    cronAllowed(
      new Request("http://x", { headers: { "X-Cron-Secret": "" } }),
      "",
    ),
    false,
  );
});

Deno.test("claims-expire: open past deadline and pending past 24 h -> expired; mismatch never expires; audited", async () => {
  const w = await payWorld();
  const open = await newSession(w);
  const pend = await newSession(w);
  await paySession(postReq(pend.token, "bkash", "PEND1234"), w.deps);
  const { session: mm } = await mismatchFlow(w);
  w.clock.now += 25 * 60 * MIN;
  const res = await expire(w, CRON);
  assert.deepEqual(await res.json(), { ok: true, sessions: 2, claims: 1 });
  assert.equal(w.store.sessions.get(open.session.id)!.status, "expired");
  assert.equal(w.store.sessions.get(pend.session.id)!.status, "expired");
  assert.equal(w.store.sessions.get(mm.id)!.status, "mismatch");
  const audit = w.store.audit.at(-1)!;
  assert.equal(audit.action, "claims.expire");
  assert.equal(audit.merchantId, null);
  assert.equal(audit.data.sessions, 2);
});

Deno.test("TrxID rules: the Edge copy answers like pay_page/logic.js", () => {
  const samples = [
    " ৯k48 x7z2 ",
    "abc",
    "24010200999",
    "AB12CD34EF56",
    "AB12CD34EF567",
    "12345678901234",
    "1234567",
  ];
  for (const s of samples) {
    assert.equal(edgeNorm(s), pageNorm(s), s);
    for (const op of ["bkash", "nagad", "rocket", "upay"] as const) {
      assert.equal(
        edgeValid(op, edgeNorm(s)),
        pageValid(op, pageNorm(s)),
        `${op} ${s}`,
      );
    }
  }
});
