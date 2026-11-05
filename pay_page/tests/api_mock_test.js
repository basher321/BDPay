import assert from "node:assert/strict";
import { createMockApi } from "../api.mock.js";

const START = Date.parse("2026-10-29T06:00:00Z");

function setup() {
  let t = START;
  const api = createMockApi({ now: () => t });
  return { api, advance: (ms) => (t += ms) };
}

Deno.test("mock session data: store, order, amount, 30-minute expiry, 4 wallets, 5 attempts", async () => {
  const { api } = setup();
  const s = await api.getSession("demo-ok");
  assert.equal(s.token, "demo-ok");
  assert.equal(s.merchantName, "নমুনা স্টোর");
  assert.equal(s.orderRef, "#1045");
  assert.equal(s.amountPoisha, 125000);
  assert.equal(Number.isInteger(s.amountPoisha), true);
  assert.equal(s.expiresAt, new Date(START + 30 * 60 * 1000).toISOString());
  assert.equal(s.status, "open");
  assert.deepEqual(
    s.operators.map((o) => `${o.operator} ${o.accountType}`),
    ["bkash merchant", "nagad merchant", "rocket agent", "upay merchant"],
  );
  assert.equal(s.attemptsLeft, 5);
  assert.equal(s.deviceOnline, true);
  assert.equal(s.submittedOperator, null);
  assert.equal(s.submittedTrxId, null);
  assert.equal(s.verifiedAt, null);
});

Deno.test("demo-ok: verified on the 3rd status check after a claim", async () => {
  const { api } = setup();
  const r = await api.submitClaim("demo-ok", "bkash", " 9k48 x7z2 ");
  assert.equal(r.result, "accepted");
  assert.equal(r.session.status, "pending");
  assert.equal(r.session.submittedTrxId, "9K48X7Z2");
  assert.equal(r.session.attemptsLeft, 4);
  assert.equal((await api.getStatus("demo-ok")).status, "pending");
  assert.equal((await api.getStatus("demo-ok")).status, "pending");
  const third = await api.getStatus("demo-ok");
  assert.equal(third.status, "verified");
  assert.notEqual(third.verifiedAt, null);
});

Deno.test("demo-ok: status checks before a claim stay open", async () => {
  const { api } = setup();
  for (let i = 0; i < 4; i++) assert.equal((await api.getStatus("demo-ok")).status, "open");
});

Deno.test("demo-mismatch: mismatch on the 2nd status check", async () => {
  const { api } = setup();
  await api.submitClaim("demo-mismatch", "nagad", "71B99AA2");
  assert.equal((await api.getStatus("demo-mismatch")).status, "pending");
  assert.equal((await api.getStatus("demo-mismatch")).status, "mismatch");
});

Deno.test("demo-slow: device offline, stays pending", async () => {
  const { api } = setup();
  const s = await api.getSession("demo-slow");
  assert.equal(s.deviceOnline, false);
  await api.submitClaim("demo-slow", "rocket", "24010200123");
  for (let i = 0; i < 10; i++) assert.equal((await api.getStatus("demo-slow")).status, "pending");
});

Deno.test("demo-expired: already expired; a claim -> expired", async () => {
  const { api } = setup();
  const s = await api.getSession("demo-expired");
  assert.equal(s.status, "expired");
  assert.ok(Date.parse(s.expiresAt) < START);
  assert.equal((await api.submitClaim("demo-expired", "bkash", "9K48X7Z2")).result, "expired");
});

Deno.test("demo-paid: already verified with TrxID 9K48X7Z2", async () => {
  const { api } = setup();
  const s = await api.getSession("demo-paid");
  assert.equal(s.status, "verified");
  assert.equal(s.submittedTrxId, "9K48X7Z2");
  assert.equal(s.submittedOperator, "bkash");
  assert.notEqual(s.verifiedAt, null);
});

Deno.test("demo-rejected (spec 07a): status rejected, TrxID 8H22K9P1 already submitted", async () => {
  const { api } = setup();
  const s = await api.getSession("demo-rejected");
  assert.equal(s.status, "rejected");
  assert.equal(s.submittedTrxId, "8H22K9P1");
  assert.equal(s.submittedOperator, "bkash");
  assert.equal((await api.getStatus("demo-rejected")).status, "rejected");
  // A new claim changes nothing.
  const r = await api.submitClaim("demo-rejected", "bkash", "9K48X7Z2");
  assert.equal(r.session.status, "rejected");
  assert.equal(r.session.attemptsLeft, s.attemptsLeft);
});

Deno.test("unknown token -> notFound everywhere", async () => {
  const { api } = setup();
  assert.deepEqual(await api.getSession("nothing"), { error: "notFound" });
  assert.deepEqual(await api.getStatus("nothing"), { error: "notFound" });
  assert.equal((await api.submitClaim("nothing", "bkash", "9K48X7Z2")).result, "notFound");
  assert.deepEqual(await api.getSession("__proto__"), { error: "notFound" });
  assert.deepEqual(await api.getSession(undefined), { error: "notFound" });
});

Deno.test("USED1234 -> alreadyUsed and uses one attempt", async () => {
  const { api } = setup();
  const r = await api.submitClaim("demo-ok", "bkash", "USED1234");
  assert.equal(r.result, "alreadyUsed");
  assert.equal(r.session.attemptsLeft, 4);
  assert.equal(r.session.status, "open");
});

Deno.test("attempts go 5 -> 0, then noAttemptsLeft", async () => {
  const { api } = setup();
  const seen = [];
  for (const trx of ["USED1234", "AAAA1111", "USED1234", "BBBB2222", "CCCC3333"]) {
    const r = await api.submitClaim("demo-slow", "bkash", trx);
    assert.ok(r.result === "accepted" || r.result === "alreadyUsed");
    seen.push(r.session.attemptsLeft);
  }
  assert.deepEqual(seen, [4, 3, 2, 1, 0]);
  const last = await api.submitClaim("demo-slow", "bkash", "DDDD4444");
  assert.equal(last.result, "noAttemptsLeft");
  assert.equal(last.session.attemptsLeft, 0);
});

Deno.test("invalid format and an operator the session doesn't offer -> invalidFormat, no attempt used", async () => {
  const { api } = setup();
  let r = await api.submitClaim("demo-ok", "rocket", "9K48X7Z2");
  assert.equal(r.result, "invalidFormat");
  r = await api.submitClaim("demo-one", "nagad", "71B99AA2");
  assert.equal(r.result, "invalidFormat");
  assert.equal(r.session.attemptsLeft, 5);
});

Deno.test("demo-one (D24): only bKash", async () => {
  const { api } = setup();
  const s = await api.getSession("demo-one");
  assert.deepEqual(s.operators.map((o) => o.operator), ["bkash"]);
});

Deno.test("D21 triggers: RATE1234 -> rateLimited; NETERR12 -> throws", async () => {
  const { api } = setup();
  const r = await api.submitClaim("demo-ok", "bkash", "RATE1234");
  assert.equal(r.result, "rateLimited");
  assert.equal(r.session.attemptsLeft, 5);
  await assert.rejects(api.submitClaim("demo-ok", "bkash", "NETERR12"));
});

Deno.test("an open session expires after 30 minutes", async () => {
  const { api, advance } = setup();
  await api.getSession("demo-ok");
  advance(30 * 60 * 1000);
  assert.equal((await api.getStatus("demo-ok")).status, "expired");
});

Deno.test("returned sessions are copies (the page can't change the server state)", async () => {
  const { api } = setup();
  const s = await api.getSession("demo-ok");
  s.attemptsLeft = 99;
  assert.equal((await api.getSession("demo-ok")).attemptsLeft, 5);
});
