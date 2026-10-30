import assert from "node:assert/strict";
import {
  alertEmail,
  alertTitleHint,
  dhakaTime,
  type Email,
  fixedEmail,
  type MessageContext,
  SIGNATURE,
  SUBJECT_PREFIX,
} from "../_shared/alert_messages.ts";
import type { AlertKind } from "../_shared/alert_rules.ts";
import { privacyLeaks } from "./privacy_scan.ts";

const SHOP = "রহিম ফ্যাশন";
const SEEN = "2026-10-30T12:00:00.000Z"; // 06:00 PM in Dhaka

const CONTEXTS: Record<AlertKind, MessageContext[]> = {
  phoneSilent: [
    { businessName: SHOP, lastSeenAt: SEEN, pendingClaimCount: 0 },
    { businessName: SHOP, lastSeenAt: SEEN, pendingClaimCount: 3 },
    // Times and dates with "01" in them must not look like phone numbers.
    { businessName: SHOP, lastSeenAt: "2026-10-31T19:05:00.000Z" },
  ],
  monitoringOff: [{ businessName: SHOP }],
  noActiveDevice: [{ businessName: SHOP }],
  shopifyReconnect: [{ businessName: SHOP }],
  reviewWaiting: [
    { businessName: SHOP, reviewWaitingCount: 1 },
    { businessName: SHOP, reviewWaitingCount: 12 },
  ],
  syncFailed: [
    { businessName: SHOP, orderRef: "#1045" },
    { businessName: SHOP, orderRef: "#1001" },
  ],
};

/** Every email this module can produce, for the shape and privacy checks. */
function everyEmail(): { label: string; mail: Email }[] {
  const out: { label: string; mail: Email }[] = [];
  for (const [kind, contexts] of Object.entries(CONTEXTS)) {
    contexts.forEach((ctx, i) =>
      out.push({
        label: `${kind}#${i}`,
        mail: alertEmail(kind as AlertKind, ctx),
      })
    );
  }
  out.push({
    label: "phoneSilent fixed",
    mail: fixedEmail("phoneSilent", SHOP),
  });
  return out;
}

Deno.test("every email: subject 'BDPay: ', text starts with the business name and ends with '— BDPay'", () => {
  for (const { label, mail } of everyEmail()) {
    assert.ok(mail.subject.startsWith(SUBJECT_PREFIX), label);
    assert.ok(mail.text.startsWith(`${SHOP},\n`), label);
    assert.ok(mail.text.endsWith(`\n${SIGNATURE}`), label);
    assert.ok(!mail.subject.includes("\n"), label);
  }
});

Deno.test("privacy scan: no TrxID, '৳' amount, phone number or email address in any email", () => {
  for (const { label, mail } of everyEmail()) {
    assert.deepEqual(privacyLeaks(mail), [], label);
  }
});

Deno.test("privacy scan catches what it must catch", () => {
  const clean = alertEmail("monitoringOff", { businessName: SHOP });
  const leak = (extra: string) => ({
    ...clean,
    text: `${clean.text}\n${extra}`,
  });
  assert.deepEqual(privacyLeaks(leak("TrxID 8H22K9P1")), ["trxId"]);
  assert.deepEqual(privacyLeaks(leak("ref 1234567890")), ["trxId"]);
  assert.deepEqual(privacyLeaks(leak("৳ 1,250.00")), ["amount"]);
  assert.deepEqual(privacyLeaks(leak("from 01712345678")), ["phone", "trxId"]);
  assert.deepEqual(privacyLeaks(leak("from +8801712345678")), [
    "phone",
    "trxId",
  ]);
  assert.deepEqual(privacyLeaks(leak("from ০১৭১২৩৪৫৬৭৮")), ["phone", "trxId"]);
  assert.deepEqual(privacyLeaks(leak("owner@example.com")), ["email"]);
  assert.deepEqual(privacyLeaks({ ...clean, subject: "BDPay: 8H22K9P1" }), [
    "trxId",
  ]);
  // Times and dates are fine.
  assert.deepEqual(privacyLeaks(leak("1 Nov 2026, 01:05 AM")), []);
});

Deno.test("phoneSilent: last seen time in Asia/Dhaka, steps, no pending line without pending claims", () => {
  const mail = alertEmail("phoneSilent", {
    businessName: SHOP,
    lastSeenAt: SEEN,
    pendingClaimCount: 0,
  });
  assert.equal(
    mail.subject,
    "BDPay: যাচাই ফোন অফলাইন — পেমেন্ট নিশ্চিত হচ্ছে না",
  );
  assert.ok(mail.text.includes("30 Oct 2026, 06:00 PM"));
  assert.ok(!mail.text.includes("অপেক্ষায় আছেন"));
  for (
    const step of [
      "ফোন চালু ও চার্জে রাখুন",
      "ইন্টারনেট দেখুন",
      "BDPay অ্যাপ খুলুন",
    ]
  ) {
    assert.ok(mail.text.includes(`- ${step}`), step);
  }
});

Deno.test("phoneSilent with pending claims: '{n} জন গ্রাহক পেমেন্ট নিশ্চিতের অপেক্ষায় আছেন'", () => {
  const mail = alertEmail("phoneSilent", {
    businessName: SHOP,
    lastSeenAt: SEEN,
    pendingClaimCount: 3,
  });
  assert.ok(
    mail.text.includes("3 জন গ্রাহক পেমেন্ট নিশ্চিতের অপেক্ষায় আছেন"),
  );
});

Deno.test("phoneSilent fixed email", () => {
  const mail = fixedEmail("phoneSilent", SHOP);
  assert.equal(mail.subject, "BDPay: যাচাই ফোন আবার সংযুক্ত হয়েছে");
});

Deno.test("subjects of the other kinds", () => {
  const subject = (kind: AlertKind, ctx: Partial<MessageContext> = {}) =>
    alertEmail(kind, { businessName: SHOP, ...ctx }).subject;
  assert.equal(subject("monitoringOff"), "BDPay: ফোনে এসএমএস দেখা বন্ধ আছে");
  assert.equal(subject("noActiveDevice"), "BDPay: কোনো যাচাই ফোন যুক্ত নেই");
  assert.equal(subject("shopifyReconnect"), "BDPay: Shopify আবার যুক্ত করুন");
  assert.equal(
    subject("reviewWaiting", { reviewWaitingCount: 2 }),
    "BDPay: 2 টি পেমেন্ট আপনার রিভিউয়ের অপেক্ষায়",
  );
  assert.equal(
    subject("syncFailed", { orderRef: "#1045" }),
    "BDPay: Shopify-তে অর্ডার #1045 'Paid' করা যায়নি",
  );
});

Deno.test("syncFailed text: verified in BDPay, mark paid by hand in Shopify admin", () => {
  const { text } = alertEmail("syncFailed", {
    businessName: SHOP,
    orderRef: "#1045",
  });
  assert.ok(text.includes("BDPay-তে নিশ্চিত হয়েছে"));
  assert.ok(text.includes("Shopify admin-এ অর্ডার #1045 খুলে হাতে 'Paid' করুন"));
});

Deno.test("alerts-list title = subject without 'BDPay: ', hint = first step", () => {
  const cases: [AlertKind, Omit<MessageContext, "businessName">][] = [
    ["phoneSilent", {}],
    ["monitoringOff", {}],
    ["noActiveDevice", {}],
    ["shopifyReconnect", {}],
    ["reviewWaiting", { reviewWaitingCount: 4 }],
    ["syncFailed", { orderRef: "#1045" }],
  ];
  for (const [kind, ctx] of cases) {
    const full = alertEmail(kind, {
      businessName: SHOP,
      lastSeenAt: SEEN,
      ...ctx,
    });
    const { title, hint } = alertTitleHint(kind, ctx);
    assert.equal(SUBJECT_PREFIX + title, full.subject, kind);
    const firstStep = full.text.split("\n").find((l) => l.startsWith("- "));
    assert.equal(`- ${hint}`, firstStep, kind);
  }
  assert.deepEqual(alertTitleHint("monitoringOff", {}), {
    title: "ফোনে এসএমএস দেখা বন্ধ আছে",
    hint: "অ্যাপ খুলে ডিভাইস স্বাস্থ্য দেখুন",
  });
});

Deno.test("dhakaTime: UTC + 6 hours, 12-hour clock, crosses midnight", () => {
  assert.equal(dhakaTime("2026-10-30T12:00:00.000Z"), "30 Oct 2026, 06:00 PM");
  assert.equal(dhakaTime("2026-10-30T18:30:00.000Z"), "31 Oct 2026, 12:30 AM");
  assert.equal(dhakaTime("2026-10-30T06:00:00.000Z"), "30 Oct 2026, 12:00 PM");
  assert.equal(dhakaTime("2026-12-31T19:05:00.000Z"), "1 Jan 2027, 01:05 AM");
  assert.throws(() => dhakaTime("soon"), RangeError);
});

Deno.test("newlines in businessName and orderRef cannot add lines or break the subject", () => {
  const mail = alertEmail("syncFailed", {
    businessName: "Shop\nBcc: x",
    orderRef: "#10\r\n45",
  });
  assert.ok(!mail.subject.includes("\n") && !mail.subject.includes("\r"));
  assert.ok(mail.text.startsWith("Shop Bcc: x,\n"));
});

Deno.test("missing or bad inputs are refused", () => {
  assert.throws(
    () => alertEmail("phoneSilent", { businessName: SHOP }),
    RangeError,
  );
  assert.throws(
    () => alertEmail("reviewWaiting", { businessName: SHOP }),
    RangeError,
  );
  assert.throws(
    () =>
      alertEmail("reviewWaiting", {
        businessName: SHOP,
        reviewWaitingCount: 1.5,
      }),
    RangeError,
  );
  assert.throws(
    () => alertEmail("syncFailed", { businessName: SHOP }),
    RangeError,
  );
  assert.throws(
    () => alertEmail("monitoringOff", { businessName: "  " }),
    RangeError,
  );
});
