// Same samples and expected values as app/test/domain/parser/parse_sms_test.dart (spec 06).
import assert from "node:assert/strict";
import rulesJson from "../_shared/parser_rules.json" with { type: "json" };
import {
  amountTextToPoisha,
  dedupeHash,
  filterSms,
  loadRules,
  normalizeSmsBody,
  parseSms,
  rulesVersion,
} from "../_shared/parser.ts";

const rules = loadRules(rulesJson);

Deno.test("the rules file has the 4 operators, version 1", () => {
  assert.deepEqual(rules.map((r) => r.operator), [
    "bkash",
    "nagad",
    "rocket",
    "upay",
  ]);
  assert.equal(rulesVersion(rules), 1);
});

Deno.test("bKash reference sample", () => {
  const p = parseSms(
    "bKash",
    "You have received payment Tk 1,250.00 from 01712345678. Ref: ORD-101. Fee Tk 0.00. " +
      "Balance Tk 15,340.50. TrxID 9K48X7Z2 at 02/10/2026 18:25",
    rules,
  );
  assert.ok(p.ok);
  assert.equal(p.operator, "bkash");
  assert.equal(p.trxId, "9K48X7Z2");
  assert.equal(p.amountPoisha, 125000);
  assert.equal(p.payerNumber, "01712345678");
  assert.equal(p.balancePoisha, 1534050);
  assert.equal(p.reference, "ORD-101");
  assert.equal(p.kind, "payment");
});

Deno.test("Nagad reference sample", () => {
  const p = parseSms(
    "NAGAD",
    "Money Received Amount: Tk 2,500.00 Sender: 01812345678 TxnID: 71B99AA2 Balance: Tk 15,000.00 " +
      "Time: 02/10/2026 14:15",
    rules,
  );
  assert.ok(p.ok);
  assert.equal(p.operator, "nagad");
  assert.equal(p.trxId, "71B99AA2");
  assert.equal(p.amountPoisha, 250000);
  assert.equal(p.payerNumber, "01812345678");
  assert.equal(p.kind, "received");
});

Deno.test("Rocket reference sample", () => {
  const p = parseSms(
    "16216",
    "Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. " +
      "TxnId: 24010200123",
    rules,
  );
  assert.ok(p.ok);
  assert.equal(p.operator, "rocket");
  assert.equal(p.trxId, "24010200123");
  assert.equal(p.amountPoisha, 150000);
  assert.equal(p.payerNumber, "017123456789");
  assert.equal(p.balancePoisha, 560000);
});

Deno.test("Upay reference sample", () => {
  const p = parseSms(
    "upay",
    "You have received Tk 800.00 from 01711223344. Txn ID: 4UP82910. Current balance Tk 3,400.00. Fee Tk 0.00.",
    rules,
  );
  assert.ok(p.ok);
  assert.equal(p.operator, "upay");
  assert.equal(p.trxId, "4UP82910");
  assert.equal(p.amountPoisha, 80000);
  assert.equal(p.payerNumber, "01711223344");
});

Deno.test('Bangla bKash sample: amount 125000 and payer from the "থেকে" form', () => {
  const p = parseSms(
    "bKash",
    "আপনি 01712345678 থেকে Tk 1,250.00 পেয়েছেন। Ref: ORDER-99। ব্যালেন্স Tk 15,340.50। TrxID 9K48X7B5",
    rules,
  );
  assert.ok(p.ok);
  assert.equal(p.amountPoisha, 125000);
  assert.equal(p.payerNumber, "01712345678");
  assert.equal(p.trxId, "9K48X7B5");
  assert.equal(p.reference, "ORDER-99");
});

Deno.test('Bangla digits "৳ ১,২৫০.০০" -> 125000', () => {
  const p = parseSms(
    "bKash",
    "আপনি ০১৭১২৩৪৫৬৭৮ থেকে ৳ ১,২৫০.০০ পেয়েছেন। TrxID 9K48X7B5",
    rules,
  );
  assert.equal(p.amountPoisha, 125000);
  assert.equal(p.payerNumber, "01712345678");
});

Deno.test("no TrxID / no amount / unknown sender -> ok false with the error", () => {
  assert.deepEqual(
    parseSms("bKash", "You have received Tk 100.00 from 01712345678.", rules)
      .errors,
    ["noTrxId"],
  );
  assert.deepEqual(
    parseSms("bKash", "You have received money. TrxID ABC12345", rules).errors,
    ["noAmount"],
  );
  const unknown = parseSms("01799999999", "TrxID ABC12345 Tk 5", rules);
  assert.deepEqual(unknown.errors, ["unknownSender"]);
  assert.equal(unknown.ok, false);
});

Deno.test('sender " BKASH " matches; TrxID is upper case', () => {
  const p = parseSms(
    " BKASH ",
    "You have received Tk 5.00 from 01712345678. TrxID abc12345",
    rules,
  );
  assert.equal(p.operator, "bkash");
  assert.equal(p.trxId, "ABC12345");
});

Deno.test('"Refund" is not a reference', () => {
  const p = parseSms(
    "bKash",
    "You have received Tk 5.00 Refund from 01712345678. TrxID ABC12345",
    rules,
  );
  assert.equal(p.reference, null);
});

Deno.test("HTML in the body is plain text", () => {
  const p = parseSms(
    "bKash",
    "You have received Tk 100.00 from 01712345678. <img src=x onerror=alert(1)> TrxID HTML1234",
    rules,
  );
  assert.ok(p.ok);
  assert.equal(p.trxId, "HTML1234");
});

Deno.test("amount text: whole-number math", () => {
  assert.equal(amountTextToPoisha("1,250.50"), 125050);
  assert.equal(amountTextToPoisha("1,250.5"), 125050);
  assert.equal(amountTextToPoisha("1,250"), 125000);
  assert.equal(amountTextToPoisha("0.5"), 50);
  assert.equal(amountTextToPoisha("0.05"), 5);
  assert.equal(amountTextToPoisha("1.234"), null);
  assert.equal(amountTextToPoisha(""), null);
  assert.equal(amountTextToPoisha("12345678901234"), null);
});

Deno.test("normalizeSmsBody: Bangla digits and Unicode spaces", () => {
  assert.equal(normalizeSmsBody("৳ ১২৩ ০"), "৳ 123 0");
});

Deno.test("filter: sender, then blocked, then notIncoming, else keep", () => {
  assert.equal(
    filterSms(rules, "01799999999", "You have received Tk 5 TrxID ABC12345")
      .result,
    "senderNotTrusted",
  );
  assert.equal(
    filterSms(rules, "bKash", "Your bKash OTP is 123456").result,
    "blocked",
  );
  assert.equal(
    filterSms(rules, "bKash", "আপনার ওটিপি ১২৩৪৫৬").result,
    "blocked",
  );
  assert.equal(
    filterSms(
      rules,
      "bKash",
      "Send Money Tk 500.00 to 01711000000 successful. TrxID ABC12345",
    ).result,
    "notIncoming",
  );
  assert.equal(
    filterSms(rules, " BKASH ", "You have received Tk 5.00. TrxID ABC12345")
      .result,
    "keep",
  );
  // "pin" inside a word is not blocked; "PIN" alone is.
  assert.equal(
    filterSms(
      rules,
      "bKash",
      "You have received Tk 5 for shopping. TrxID ABC12345",
    )
      .result,
    "keep",
  );
});

Deno.test("dedupe hash = Kotlin's SHA-256(lower(trim(sender)) + '|' + body)", async () => {
  // Expected value computed outside Deno: printf '%s' 'bkash|...' | sha256sum
  assert.equal(
    await dedupeHash(
      " bKash ",
      "You have received Tk 5.00 from 01712345678. TrxID abc12345",
    ),
    "4f948b7eb882f1ef23aa68c2115e7e76c8e89a2a2280e327a27250f8868820bc",
  );
});

Deno.test("loadRules refuses a bad file with a fixed message", () => {
  assert.throws(() => loadRules({}), RangeError);
  assert.throws(() => loadRules([{ operator: "paypal" }]), RangeError);
  const bad = structuredClone(rulesJson) as Record<string, unknown>[];
  bad[0].trx = "(";
  assert.throws(() => loadRules(bad), /rules: bad pattern trx/);
});
