import assert from "node:assert/strict";
import {
  canonicalTrxId,
  evaluate,
  type MatchClaim,
  type MatchSession,
  type MatchSms,
} from "../_shared/match_rules.ts";

const CREATED = "2026-10-29T06:00:00.000Z";
const DEADLINE = "2026-10-30T06:05:00.000Z"; // claim created 06:05 + 24 h

const at = (base: string, ms: number) =>
  new Date(Date.parse(base) + ms).toISOString();
const MIN = 60 * 1000;

function fixture(): {
  session: MatchSession;
  claim: MatchClaim;
  sms: MatchSms;
} {
  return {
    session: { merchantId: "m1", amountPoisha: 45000, createdAt: CREATED },
    claim: {
      merchantId: "m1",
      operator: "bkash",
      trxId: "8H22K9P1",
      matchDeadline: DEADLINE,
    },
    sms: {
      merchantId: "m1",
      operator: "bkash",
      trxId: "8H22K9P1",
      amountPoisha: 45000,
      status: "unmatched",
      receivedAt: at(CREATED, 3 * MIN),
    },
  };
}

Deno.test("all rules pass and amounts equal -> verified", () => {
  const { session, claim, sms } = fixture();
  assert.deepEqual(evaluate(session, claim, sms), {
    result: "verified",
    reason: null,
  });
});

Deno.test("amounts differ -> mismatch, reason amount (43000 vs 45000)", () => {
  const { session, claim, sms } = fixture();
  assert.deepEqual(evaluate(session, claim, { ...sms, amountPoisha: 43000 }), {
    result: "mismatch",
    reason: "amount",
  });
});

Deno.test("rule 1 alone: another merchant's SMS -> noMatch", () => {
  const { session, claim, sms } = fixture();
  assert.deepEqual(evaluate(session, claim, { ...sms, merchantId: "m2" }), {
    result: "noMatch",
    reason: "merchant",
  });
  assert.equal(
    evaluate({ ...session, merchantId: "m2" }, claim, sms).result,
    "noMatch",
  );
});

Deno.test("rule 2 alone: another operator -> noMatch", () => {
  const { session, claim, sms } = fixture();
  assert.deepEqual(evaluate(session, claim, { ...sms, operator: "nagad" }), {
    result: "noMatch",
    reason: "operator",
  });
});

Deno.test("rule 3 alone: another TrxID -> noMatch", () => {
  const { session, claim, sms } = fixture();
  assert.deepEqual(evaluate(session, claim, { ...sms, trxId: "8H22K9P2" }), {
    result: "noMatch",
    reason: "trxId",
  });
});

Deno.test("rule 3: case and outer spaces don't matter; empty never matches", () => {
  const { session, claim, sms } = fixture();
  assert.equal(
    evaluate(session, claim, { ...sms, trxId: " 8h22k9p1 " }).result,
    "verified",
  );
  assert.equal(
    evaluate(session, { ...claim, trxId: " " }, { ...sms, trxId: "" }).result,
    "noMatch",
  );
  assert.equal(canonicalTrxId(" 9k48x7z2 "), "9K48X7Z2");
});

Deno.test("rule 4 alone: SMS not unmatched -> noMatch", () => {
  const { session, claim, sms } = fixture();
  for (const status of ["matched", "rejected", "received"] as const) {
    assert.deepEqual(evaluate(session, claim, { ...sms, status }), {
      result: "noMatch",
      reason: "smsStatus",
    }, status);
  }
});

Deno.test("rule 5 alone: SMS 2 hours before the order -> noMatch", () => {
  const { session, claim, sms } = fixture();
  assert.deepEqual(
    evaluate(session, claim, { ...sms, receivedAt: at(CREATED, -120 * MIN) }),
    { result: "noMatch", reason: "tooEarly" },
  );
});

Deno.test("rule 5 boundary: exactly 30 min before = candidate; 30 min 1 s = not", () => {
  const { session, claim, sms } = fixture();
  assert.equal(
    evaluate(session, claim, { ...sms, receivedAt: at(CREATED, -30 * MIN) })
      .result,
    "verified",
  );
  assert.deepEqual(
    evaluate(session, claim, {
      ...sms,
      receivedAt: at(CREATED, -30 * MIN - 1000),
    }),
    { result: "noMatch", reason: "tooEarly" },
  );
});

Deno.test("rule 6 alone: SMS after the match deadline -> noMatch; at the deadline -> candidate", () => {
  const { session, claim, sms } = fixture();
  assert.deepEqual(
    evaluate(session, claim, { ...sms, receivedAt: at(DEADLINE, 1000) }),
    { result: "noMatch", reason: "tooLate" },
  );
  assert.equal(
    evaluate(session, claim, { ...sms, receivedAt: DEADLINE }).result,
    "verified",
  );
});

Deno.test("SMS first (before the claim, after the session) is still a candidate", () => {
  const { session, claim, sms } = fixture();
  assert.equal(
    evaluate(session, claim, { ...sms, receivedAt: at(CREATED, -5 * MIN) })
      .result,
    "verified",
  );
});

Deno.test("money must be whole poisha; bad times throw", () => {
  const { session, claim, sms } = fixture();
  assert.throws(
    () => evaluate(session, claim, { ...sms, amountPoisha: 450.5 }),
    RangeError,
  );
  assert.throws(
    () => evaluate({ ...session, amountPoisha: -1 }, claim, sms),
    RangeError,
  );
  assert.throws(
    () => evaluate(session, claim, { ...sms, receivedAt: "yesterday" }),
    RangeError,
  );
});

Deno.test("evaluate is pure: inputs are not changed", () => {
  const f = fixture();
  const before = structuredClone(f);
  evaluate(f.session, f.claim, f.sms);
  assert.deepEqual(f, before);
});
