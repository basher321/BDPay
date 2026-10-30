// Spec 09 pay-session: GET Session JSON, every POST result, both arrival orders, superseding, CORS, rate limits,
// the race and the notifier.
import assert from "node:assert/strict";
import { handle } from "../_shared/pay_session.ts";
import {
  addSms,
  getReq,
  newSession,
  ORIGIN,
  payWorld,
  postReq,
} from "./helpers/pay_world.ts";
import { MIN } from "./helpers/world.ts";

async function post(
  w: Awaited<ReturnType<typeof payWorld>>,
  token: string,
  op: string,
  trx: string,
  ip?: string,
) {
  const res = await handle(postReq(token, op, trx, ip), w.deps);
  return { status: res.status, body: await res.json() };
}

Deno.test("GET: the spec 07 Session JSON; expiresAt = submitDeadline while open", async () => {
  const w = await payWorld();
  const { token, session } = await newSession(w);
  const res = await handle(getReq(token), w.deps);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("Cache-Control"), "no-store");
  assert.deepEqual(await res.json(), {
    token,
    merchantName: "নমুনা স্টোর",
    orderRef: "#1045",
    amountPoisha: 125000,
    expiresAt: session.submitDeadline,
    status: "open",
    operators: [
      {
        operator: "bkash",
        walletNumber: "01700000001",
        accountType: "merchant",
      },
      {
        operator: "rocket",
        walletNumber: "017000000031",
        accountType: "agent",
      },
    ],
    attemptsLeft: 5,
    returnUrl: "https://shop.example.com/orders/1045",
    deviceOnline: true,
    submittedOperator: null,
    submittedTrxId: null,
    verifiedAt: null,
  });
});

Deno.test("GET: pending -> the claim's matchDeadline; verified -> null; unknown or bad token -> 404", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  await post(w, token, "bkash", "AB12CD34");
  const pending = await (await handle(getReq(token), w.deps)).json();
  assert.equal(pending.status, "pending");
  assert.equal(
    pending.expiresAt,
    new Date(w.clock.now + 24 * 60 * MIN).toISOString(),
  );
  assert.equal(pending.submittedTrxId, "AB12CD34");
  await addSms(w, "AB12CD34");
  await w.deps.matcher.onSmsStored(w.store.sms.at(-1)!);
  const verified = await (await handle(getReq(token), w.deps)).json();
  assert.equal(verified.status, "verified");
  assert.equal(verified.expiresAt, null);
  assert.equal((await handle(getReq("x".repeat(43)), w.deps)).status, 404);
  assert.equal((await handle(getReq("short"), w.deps)).status, 404);
});

Deno.test("GET: open past the deadline shows expired; device offline after 10 minutes", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  w.clock.now += 61 * MIN;
  const s = await (await handle(getReq(token), w.deps)).json();
  assert.equal(s.status, "expired");
  assert.equal(s.deviceOnline, false);
});

Deno.test("GET: the 61st call in a minute for one token -> 429", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  for (let i = 0; i < 60; i++) {
    assert.equal((await handle(getReq(token), w.deps)).status, 200);
  }
  assert.equal((await handle(getReq(token), w.deps)).status, 429);
});

Deno.test("POST: SMS first, TrxID later -> verified at once (Bangla digits and spaces normalized)", async () => {
  const w = await payWorld();
  const { token, session } = await newSession(w);
  await addSms(w, "9K48X7Z2");
  const r = await post(w, token, "bkash", " ৯k48 x7z2 ");
  assert.equal(r.body.result, "accepted");
  assert.equal(r.body.session.status, "verified");
  assert.deepEqual(w.notifier.verified, [session.id]);
});

Deno.test("POST: TrxID first, SMS later -> verified when the SMS arrives (matcher)", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  assert.equal(
    (await post(w, token, "bkash", "AB12CD34")).body.session.status,
    "pending",
  );
  const sms = await addSms(w, "AB12CD34");
  assert.deepEqual(await w.deps.matcher.onSmsStored(sms), {
    verifyStatus: "verified",
    serverMessage: "অর্ডারের সাথে মিলেছে",
  });
  assert.equal(w.notifier.verified.length, 1);
});

Deno.test("POST: wrong amount -> mismatch", async () => {
  const w = await payWorld();
  const { token } = await newSession(w, { amountPoisha: 45000 });
  await addSms(w, "MM12CD34", { amountPoisha: 43000 });
  const r = await post(w, token, "bkash", "MM12CD34");
  assert.equal(r.body.session.status, "mismatch");
  assert.equal(w.notifier.verified.length, 0);
});

Deno.test("POST: change the TrxID while pending supersedes; attempts 5 -> 4 -> 3; the same TrxID twice uses none", async () => {
  const w = await payWorld();
  const { token, session } = await newSession(w);
  assert.equal(
    (await post(w, token, "bkash", "AAAA1111")).body.session.attemptsLeft,
    4,
  );
  assert.equal(
    (await post(w, token, "bkash", "AAAA1111")).body.session.attemptsLeft,
    4,
  );
  const r = await post(w, token, "bkash", "BBBB2222");
  assert.equal(r.body.session.attemptsLeft, 3);
  assert.equal(r.body.session.submittedTrxId, "BBBB2222");
  const claims = [...w.store.claims.values()].filter((c) =>
    c.sessionId === session.id
  );
  assert.deepEqual(claims.map((c) => c.status).sort(), [
    "pending",
    "superseded",
  ]);
});

Deno.test("POST: attempts to 0 -> noAttemptsLeft", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  for (
    const t of ["AAAA0001", "AAAA0002", "AAAA0003", "AAAA0004", "AAAA0005"]
  ) {
    assert.equal((await post(w, token, "bkash", t)).body.result, "accepted");
  }
  assert.equal(
    (await post(w, token, "bkash", "AAAA0006")).body.result,
    "noAttemptsLeft",
  );
});

Deno.test("POST: a TrxID that verified another order -> alreadyUsed (one attempt used)", async () => {
  const w = await payWorld();
  const first = await newSession(w);
  await addSms(w, "USED1234");
  assert.equal(
    (await post(w, first.token, "bkash", "USED1234")).body.session.status,
    "verified",
  );
  const second = await newSession(w);
  const r = await post(w, second.token, "bkash", "USED1234");
  assert.equal(r.body.result, "alreadyUsed");
  assert.equal(r.body.session.attemptsLeft, 4);
});

Deno.test("POST: bad format, an operator not offered -> invalidFormat (no attempt); unknown token -> notFound", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  assert.equal(
    (await post(w, token, "bkash", "AB1")).body.result,
    "invalidFormat",
  );
  assert.equal(
    (await post(w, token, "rocket", "AB12CD34")).body.result,
    "invalidFormat",
  );
  const nagad = await post(w, token, "nagad", "AB12CD34");
  assert.equal(nagad.body.result, "invalidFormat");
  assert.equal(nagad.body.session.attemptsLeft, 5);
  assert.equal(
    (await post(w, "y".repeat(43), "bkash", "AB12CD34")).body.result,
    "notFound",
  );
});

Deno.test("POST: past the submit deadline -> expired; verified stays accepted with no change", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  w.clock.now += 61 * MIN;
  assert.equal(
    (await post(w, token, "bkash", "AB12CD34")).body.result,
    "expired",
  );
  const w2 = await payWorld();
  const s2 = await newSession(w2);
  await addSms(w2, "PAID1234");
  await post(w2, s2.token, "bkash", "PAID1234");
  const again = await post(w2, s2.token, "bkash", "OTHER123");
  assert.equal(again.body.result, "accepted");
  assert.equal(again.body.session.submittedTrxId, "PAID1234");
});

Deno.test("POST: the 21st POST from one IP in 10 minutes -> rateLimited (429)", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  for (let i = 0; i < 20; i++) {
    await post(w, token, "bkash", "AB1", "198.51.100.1");
  }
  const r = await post(w, token, "bkash", "AB1", "198.51.100.1");
  assert.equal(r.status, 429);
  assert.equal(r.body.result, "rateLimited");
  assert.equal(
    (await post(w, token, "bkash", "AB1", "198.51.100.2")).status,
    200,
  );
});

Deno.test("CORS: headers only for PAY_PAGE_ORIGIN; OPTIONS answered", async () => {
  const w = await payWorld();
  const { token } = await newSession(w);
  const ok = await handle(getReq(token, ORIGIN), w.deps);
  assert.equal(ok.headers.get("Access-Control-Allow-Origin"), ORIGIN);
  const other = await handle(getReq(token, "https://evil.example"), w.deps);
  assert.equal(other.headers.get("Access-Control-Allow-Origin"), null);
  const pre = await handle(
    new Request("http://localhost/pay-session", {
      method: "OPTIONS",
      headers: { Origin: ORIGIN },
    }),
    w.deps,
  );
  assert.equal(pre.status, 204);
  assert.match(pre.headers.get("Access-Control-Allow-Methods")!, /POST/);
  w.deps.config = { ...w.deps.config, payPageOrigin: "" };
  assert.equal(
    (await handle(getReq(token, ORIGIN), w.deps)).headers.get(
      "Access-Control-Allow-Origin",
    ),
    null,
  );
});

Deno.test("race: submit and onSmsStored in parallel -> exactly one match; both report verified", async () => {
  const w = await payWorld();
  const { token, session } = await newSession(w);
  const sms = await addSms(w, "RACE1234");
  let release!: () => void;
  w.store.gate = new Promise<void>((r) => (release = r));
  const submit = post(w, token, "bkash", "RACE1234");
  // Wait until submit has created its claim and is held at findUnmatchedSms.
  for (let i = 0; i < 200 && w.store.claims.size === 0; i++) {
    await new Promise((r) => setTimeout(r, 1));
  }
  assert.equal(w.store.claims.size, 1);
  // The matcher now reads the pending claim and is held too: both saw "pending claim + unmatched SMS".
  const matched = w.deps.matcher.onSmsStored(sms);
  await new Promise((r) => setTimeout(r, 5));
  release();
  w.store.gate = null;
  const [p, m] = await Promise.all([submit, matched]);
  assert.equal(w.store.matches.length, 1);
  assert.equal(p.body.session.status, "verified");
  assert.equal(m.verifyStatus, "verified");
  assert.deepEqual(w.notifier.verified, [session.id]);
});

Deno.test("notifier throws -> the session stays verified; the error is logged by code only", async () => {
  const w = await payWorld();
  w.notifier.throws = true;
  const { token } = await newSession(w);
  await addSms(w, "NOTI1234");
  const r = await post(w, token, "bkash", "NOTI1234");
  assert.equal(r.body.session.status, "verified");
  assert.ok(w.logs.some((l) => l.code === "notifierFailed"));
  assert.ok(!JSON.stringify(w.logs).includes("NOTI1234"));
  assert.ok(!JSON.stringify(w.logs).includes(token));
});
