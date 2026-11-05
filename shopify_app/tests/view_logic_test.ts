import assert from "node:assert/strict";
import {
  decideView,
  isSafePayUrl,
  nextRetryDelay,
  parsePaylinkAnswer,
  type PaylinkResult,
} from "../extensions/bdpay-pay-box/src/view_logic.ts";

// A reserved address that can never resolve (no real URL in this folder).
const PAY = "https://pay.example.invalid/?t=dev";
const ready = (sessionStatus: string): PaylinkResult => ({
  status: "ready",
  payUrl: PAY,
  sessionStatus,
});

Deno.test("notBdpay -> hidden", () => {
  assert.equal(decideView({ status: "notBdpay" }, 0), "hidden");
});

Deno.test("alreadyPaid -> paid; ready + verified -> paid", () => {
  assert.equal(decideView({ status: "alreadyPaid" }, 0), "paid");
  assert.equal(decideView(ready("verified"), 0), "paid");
});

Deno.test("ready + open -> payNow", () => {
  assert.equal(decideView(ready("open"), 0), "payNow");
});

Deno.test("ready + pending or mismatch -> pending", () => {
  assert.equal(decideView(ready("pending"), 0), "pending");
  assert.equal(decideView(ready("mismatch"), 0), "pending");
});

Deno.test("ready + expired or rejected -> hidden", () => {
  assert.equal(decideView(ready("expired"), 0), "hidden");
  assert.equal(decideView(ready("rejected"), 0), "hidden");
});

Deno.test("ready + an unknown sessionStatus -> hidden (never a pay button)", () => {
  assert.equal(decideView(ready("something-new"), 0), "hidden");
  assert.equal(decideView(ready(""), 0), "hidden");
});

Deno.test("notReady at attempts 0, 9, 10 -> loading, loading, waitLonger", () => {
  const r: PaylinkResult = { status: "notReady" };
  assert.equal(decideView(r, 0), "loading");
  assert.equal(decideView(r, 9), "loading");
  assert.equal(decideView(r, 10), "waitLonger");
  assert.equal(decideView(r, 25), "waitLonger");
});

Deno.test("error at attempts 0, 1, 2 -> loading, loading, failed", () => {
  const r: PaylinkResult = { status: "error" };
  assert.equal(decideView(r, 0), "loading");
  assert.equal(decideView(r, 1), "loading");
  assert.equal(decideView(r, 2), "failed");
});

Deno.test("nextRetryDelay: 3000 while a retry is due, else null", () => {
  for (let a = 0; a <= 9; a++) {
    assert.equal(
      nextRetryDelay({ status: "notReady" }, a),
      3000,
      `notReady ${a}`,
    );
  }
  assert.equal(nextRetryDelay({ status: "notReady" }, 10), null);
  assert.equal(nextRetryDelay({ status: "error" }, 0), 3000);
  assert.equal(nextRetryDelay({ status: "error" }, 1), 3000);
  assert.equal(nextRetryDelay({ status: "error" }, 2), null);
  // final views never retry
  for (
    const r of [
      { status: "notBdpay" },
      { status: "alreadyPaid" },
      ready("open"),
      ready("pending"),
      ready("verified"),
      ready("expired"),
    ] as PaylinkResult[]
  ) {
    assert.equal(nextRetryDelay(r, 0), null, JSON.stringify(r));
  }
});

Deno.test("paid only from the backend's answer", () => {
  const all: PaylinkResult[] = [
    { status: "notBdpay" },
    { status: "alreadyPaid" },
    { status: "notReady" },
    { status: "error" },
    ...["open", "pending", "mismatch", "verified", "expired", "rejected"].map(
      ready,
    ),
  ];
  const paid = all.filter((r) => decideView(r, 0) === "paid");
  assert.deepEqual(paid, [{ status: "alreadyPaid" }, ready("verified")]);
});

Deno.test("isSafePayUrl: https only, no user info", () => {
  assert.equal(isSafePayUrl(PAY), true);
  assert.equal(isSafePayUrl("http://pay.example.invalid/"), false);
  assert.equal(isSafePayUrl("javascript:alert(1)"), false);
  assert.equal(isSafePayUrl("https://user:pass@pay.example.invalid/"), false);
  assert.equal(isSafePayUrl("/relative"), false);
  assert.equal(isSafePayUrl(42), false);
});

Deno.test("parsePaylinkAnswer keeps only status / payUrl / sessionStatus", () => {
  assert.deepEqual(
    parsePaylinkAnswer(200, {
      ok: true,
      status: "ready",
      payUrl: PAY,
      sessionStatus: "open",
      amountPoisha: 125000,
      walletNumber: "01700000001",
      trxId: "9K48X7Z2",
    }),
    { status: "ready", payUrl: PAY, sessionStatus: "open" },
  );
  assert.deepEqual(
    parsePaylinkAnswer(200, { ok: true, status: "notBdpay", amountPoisha: 1 }),
    {
      status: "notBdpay",
    },
  );
  assert.deepEqual(parsePaylinkAnswer(200, { status: "alreadyPaid" }), {
    status: "alreadyPaid",
  });
  assert.deepEqual(parsePaylinkAnswer(200, { status: "notReady" }), {
    status: "notReady",
  });
});

Deno.test("parsePaylinkAnswer: anything unexpected -> error", () => {
  const bad: [number, unknown][] = [
    [401, { ok: false, error: "badSessionToken" }],
    [429, {}],
    [500, null],
    [200, null],
    [200, "ready"],
    [200, { status: "weird" }],
    [200, {
      status: "ready",
      payUrl: "http://x.invalid/",
      sessionStatus: "open",
    }],
    [200, {
      status: "ready",
      payUrl: "javascript:alert(1)",
      sessionStatus: "open",
    }],
    [200, { status: "ready", payUrl: PAY }],
  ];
  for (const [code, body] of bad) {
    assert.deepEqual(
      parsePaylinkAnswer(code, body),
      { status: "error" },
      JSON.stringify([code, body]),
    );
  }
});
