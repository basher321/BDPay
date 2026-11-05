import assert from "node:assert/strict";
import {
  formatCountdown,
  formatDhakaTime,
  formatPoisha,
  isSafeReturnUrl,
  isValidTrxId,
  nextPollDelay,
  normalizeTrxId,
  TimeoutError,
  withTimeout,
} from "../logic.js";

Deno.test("formatPoisha: the spec and app examples", () => {
  assert.equal(formatPoisha(125000), "৳ 1,250.00");
  assert.equal(formatPoisha(125050), "৳ 1,250.50");
  assert.equal(formatPoisha(0), "৳ 0.00");
  assert.equal(formatPoisha(123456789), "৳ 1,234,567.89");
  assert.equal(formatPoisha(5), "৳ 0.05");
  assert.equal(formatPoisha(100000000), "৳ 1,000,000.00");
});

Deno.test("formatPoisha: negative, fractional or non-numbers throw", () => {
  assert.throws(() => formatPoisha(-1), RangeError);
  assert.throws(() => formatPoisha(1.5), RangeError);
  assert.throws(() => formatPoisha("125000"), RangeError);
  assert.throws(() => formatPoisha(Number.MAX_SAFE_INTEGER + 1), RangeError);
});

Deno.test("normalizeTrxId: spaces, case and Bangla digits", () => {
  assert.equal(normalizeTrxId(" 9k48 x7z2 "), "9K48X7Z2");
  assert.equal(normalizeTrxId("২৪০১০২০০১২৩"), "24010200123");
  assert.equal(normalizeTrxId("71b9 9aa2"), "71B99AA2");
  assert.equal(normalizeTrxId(""), "");
  assert.equal(normalizeTrxId(undefined), "");
});

Deno.test("isValidTrxId: bkash / nagad / upay 8-12 letters or digits", () => {
  for (const op of ["bkash", "nagad", "upay"]) {
    assert.equal(isValidTrxId(op, "9K48X7Z2"), true, op);
    assert.equal(isValidTrxId(op, "ABCDEFGH1234"), true, op);
    assert.equal(isValidTrxId(op, "9K48X7Z"), false, op); // 7
    assert.equal(isValidTrxId(op, "ABCDEFGH12345"), false, op); // 13
    assert.equal(isValidTrxId(op, "9K48-X7Z2"), false, op);
    assert.equal(isValidTrxId(op, "9k48x7z2"), false, op); // must be normalized first
  }
});

Deno.test("isValidTrxId: rocket 8-14 digits only", () => {
  assert.equal(isValidTrxId("rocket", "24010200123"), true);
  assert.equal(isValidTrxId("rocket", "12345678"), true); // 8
  assert.equal(isValidTrxId("rocket", "12345678901234"), true); // 14
  assert.equal(isValidTrxId("rocket", "1234567"), false); // 7
  assert.equal(isValidTrxId("rocket", "123456789012345"), false); // 15
  assert.equal(isValidTrxId("rocket", "9K48X7Z2"), false); // letters
});

Deno.test("isValidTrxId: unknown operator is never valid", () => {
  assert.equal(isValidTrxId("paypal", "9K48X7Z2"), false);
  assert.equal(isValidTrxId("__proto__", "9K48X7Z2"), false);
});

Deno.test("formatCountdown: mm:ss, hh:mm:ss, 00:00", () => {
  assert.equal(formatCountdown(0), "00:00");
  assert.equal(formatCountdown(-5000), "00:00");
  assert.equal(formatCountdown(400), "00:01"); // rounded up
  assert.equal(formatCountdown(59999), "01:00");
  assert.equal(formatCountdown(60000), "01:00");
  assert.equal(formatCountdown(30 * 60 * 1000), "30:00");
  assert.equal(formatCountdown(3599000), "59:59");
  assert.equal(formatCountdown(3600000), "01:00:00");
  assert.equal(formatCountdown(3661000), "01:01:01");
});

Deno.test("nextPollDelay: 3 s for 2 minutes, then 10 s", () => {
  assert.equal(nextPollDelay(0), 3000);
  assert.equal(nextPollDelay(119999), 3000);
  assert.equal(nextPollDelay(120000), 10000);
  assert.equal(nextPollDelay(600000), 10000);
});

Deno.test("formatDhakaTime: UTC -> Asia/Dhaka (UTC+6)", () => {
  assert.equal(formatDhakaTime("2026-10-29T12:25:00Z"), "29 Oct 2026, 06:25 PM");
  assert.equal(formatDhakaTime("2026-10-28T18:00:00Z"), "29 Oct 2026, 12:00 AM");
  assert.equal(formatDhakaTime("not a date"), "");
});

Deno.test("isSafeReturnUrl: https, or http on localhost only", () => {
  assert.equal(isSafeReturnUrl("https://shop.myshopify.com/orders/1"), true);
  assert.equal(isSafeReturnUrl("http://127.0.0.1:8080/"), true);
  assert.equal(isSafeReturnUrl("http://localhost/"), true);
  assert.equal(isSafeReturnUrl("http://shop.com/"), false);
  assert.equal(isSafeReturnUrl("javascript:alert(1)"), false);
  assert.equal(isSafeReturnUrl("JavaScript:alert(1)"), false);
  assert.equal(isSafeReturnUrl("data:text/html,<b>x</b>"), false);
  assert.equal(isSafeReturnUrl("/relative"), false);
  assert.equal(isSafeReturnUrl(""), false);
  assert.equal(isSafeReturnUrl(null), false);
});

Deno.test("withTimeout: resolves in time, rejects with TimeoutError when late", async () => {
  assert.equal(await withTimeout(Promise.resolve(7), 50), 7);
  const late = new Promise((r) => setTimeout(() => r(1), 200));
  await assert.rejects(withTimeout(late, 20), TimeoutError);
  await late; // let its timer finish so the test leaves no timers
});
