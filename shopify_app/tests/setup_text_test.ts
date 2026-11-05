import assert from "node:assert/strict";
import text from "../MERCHANT_SETUP_BN.txt" with { type: "text" };

Deno.test("MERCHANT_SETUP_BN.txt has the release marker", () => {
  assert.ok(
    text.includes(
      "Check the Shopify menu names before release; they may change.",
    ),
  );
});

Deno.test("MERCHANT_SETUP_BN.txt has the 5 numbered steps from the spec", () => {
  const steps = [
    "1. BDPay অ্যাপে Shopify যুক্ত করুন (সেটিংস > Shopify স্টোর).",
    "2. Shopify অ্যাডমিন > Settings > Payments > Manual payment methods > Create custom payment method.",
    'নামে অবশ্যই "BDPay" শব্দটি রাখুন, যেমন: "bKash / Nagad (BDPay)".',
    "3. Shopify অ্যাডমিন > Settings > Checkout > Customize: Thank you পেজে এবং Order status পেজে",
    '"BDPay pay box" ব্লক যোগ করে Save করুন.',
    "4. স্টোরের মুদ্রা BDT রাখুন.",
    '5. একটি পরীক্ষামূলক অর্ডার দিয়ে দেখুন "এখনই পেমেন্ট করুন" বোতাম দেখা যাচ্ছে কিনা.',
  ];
  for (const s of steps) assert.ok(text.includes(s), s);
  assert.equal((text.match(/^\d\. /gm) ?? []).length, 5);
});

Deno.test("no URL in the setup text", () => {
  assert.ok(!/https?:\/\//.test(text));
});
