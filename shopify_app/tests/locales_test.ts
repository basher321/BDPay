import assert from "node:assert/strict";

import enJson from "../extensions/bdpay-pay-box/locales/en.default.json" with {
  type: "json",
};
import bnJson from "../extensions/bdpay-pay-box/locales/bn.json" with {
  type: "json",
};

/** "a.b" -> value, for every leaf. */
function leaves(
  obj: Record<string, unknown>,
  prefix = "",
): Map<string, unknown> {
  const out = new Map<string, unknown>();
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (v !== null && typeof v === "object" && !Array.isArray(v)) {
      for (const [k2, v2] of leaves(v as Record<string, unknown>, key)) {
        out.set(k2, v2);
      }
    } else {
      out.set(key, v);
    }
  }
  return out;
}

const en = leaves(enJson as Record<string, unknown>);
const bn = leaves(bnJson as Record<string, unknown>);

Deno.test("en.default.json and bn.json have the same keys", () => {
  assert.deepEqual([...bn.keys()].sort(), [...en.keys()].sort());
});

Deno.test("no empty texts", () => {
  for (const [k, v] of [...en, ...bn]) {
    assert.ok(typeof v === "string" && v.trim() !== "", k);
  }
});

Deno.test("Bangla texts are exactly the spec's", () => {
  assert.deepEqual(Object.fromEntries(bn), {
    "name": "BDPay pay box",
    "payNow.heading": "bKash / Nagad দিয়ে পেমেন্ট সম্পন্ন করুন",
    "payNow.text": "অর্ডার নিশ্চিত করতে এখনই পেমেন্ট করুন এবং TrxID দিন।",
    "payNow.button": "এখনই পেমেন্ট করুন",
    "pending.title": "পেমেন্ট যাচাই হচ্ছে",
    "pending.link": "অবস্থা দেখুন",
    "paid.title": "পেমেন্ট নিশ্চিত হয়েছে ✓",
    "waitLonger.text": "পেমেন্ট লিংক তৈরি হচ্ছে — একটু পরে পেজটি রিফ্রেশ করুন",
    "failed.text": "পেমেন্ট লিংক লোড হয়নি — পেজটি রিফ্রেশ করুন",
  });
});

Deno.test("no URL in any locale text", () => {
  for (const [k, v] of [...en, ...bn]) {
    assert.ok(!/https?:\/\//.test(String(v)), k);
  }
});
