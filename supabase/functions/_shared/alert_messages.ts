// Spec 11 alert emails: pure functions, plain text, Bangla.
// The inputs are only businessName, counts, a time and orderRef. There is no way for a TrxID, amount, payer
// number, SMS text, token or email address to reach a message.

import type { AlertKind } from "./alert_rules.ts";

export interface MessageContext {
  businessName: string;
  /** phoneSilent: the newest device seen time (ISO UTC). */
  lastSeenAt?: string | null;
  /** phoneSilent: claims waiting for the phone. */
  pendingClaimCount?: number;
  /** reviewWaiting: mismatch claims waiting for review. */
  reviewWaitingCount?: number;
  /** syncFailed: the Shopify order name, for example "#1045". */
  orderRef?: string;
}

export interface Email {
  subject: string;
  text: string;
}

export interface TitleHint {
  title: string;
  hint: string;
}

export const SUBJECT_PREFIX = "BDPay: ";
export const SIGNATURE = "— BDPay";

const DHAKA_OFFSET_MS = 6 * 60 * 60 * 1000;
const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

const two = (n: number) => String(n).padStart(2, "0");

/** "29 Oct 2026, 06:25 PM" in Asia/Dhaka (UTC+6, no daylight saving). */
export function dhakaTime(iso: string): string {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) throw new RangeError("invalid time");
  const d = new Date(t + DHAKA_OFFSET_MS);
  const h = d.getUTCHours();
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}, ${
    two(h12)
  }:${two(d.getUTCMinutes())} ${h < 12 ? "AM" : "PM"}`;
}

/** One line of plain text: control characters (newlines included) become spaces. */
function oneLine(text: string): string {
  // deno-lint-ignore no-control-regex
  return text.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ")
    .trim();
}

function count(value: number | undefined): number {
  if (value === undefined || !Number.isSafeInteger(value) || value < 0) {
    throw new RangeError("count must be a whole, non-negative number");
  }
  return value;
}

function orderRef(ctx: MessageContext): string {
  const ref = oneLine(ctx.orderRef ?? "");
  if (ref === "") throw new RangeError("orderRef is required");
  return ref;
}

interface Parts {
  title: string;
  body: string[];
  steps: string[];
}

/** Title (the subject without "BDPay: ") and the steps. Needs only counts and orderRef. */
function head(kind: AlertKind, ctx: MessageContext): Omit<Parts, "body"> {
  switch (kind) {
    case "phoneSilent":
      return {
        title: "যাচাই ফোন অফলাইন — পেমেন্ট নিশ্চিত হচ্ছে না",
        steps: [
          "ফোন চালু ও চার্জে রাখুন",
          "ইন্টারনেট দেখুন",
          "BDPay অ্যাপ খুলুন",
        ],
      };
    case "monitoringOff":
      return {
        title: "ফোনে এসএমএস দেখা বন্ধ আছে",
        steps: [
          "অ্যাপ খুলে ডিভাইস স্বাস্থ্য দেখুন",
          "এসএমএস অনুমতি ও মনিটরিং চালু করুন",
        ],
      };
    case "noActiveDevice":
      return {
        title: "কোনো যাচাই ফোন যুক্ত নেই",
        steps: [
          "যে ফোনে bKash/Nagad সিম আছে সেই ফোনে BDPay অ্যাপে লগইন করুন",
        ],
      };
    case "shopifyReconnect":
      return {
        title: "Shopify আবার যুক্ত করুন",
        steps: ["অ্যাপ > সেটিংস > Shopify স্টোর > আবার যুক্ত করুন"],
      };
    case "reviewWaiting":
      return {
        title: `${
          count(ctx.reviewWaitingCount)
        } টি পেমেন্ট আপনার রিভিউয়ের অপেক্ষায়`,
        steps: ['অ্যাপ > লেনদেন > "টাকা মেলেনি" দেখুন'],
      };
    case "syncFailed": {
      const ref = orderRef(ctx);
      return {
        title: `Shopify-তে অর্ডার ${ref} 'Paid' করা যায়নি`,
        steps: [`Shopify admin-এ অর্ডার ${ref} খুলে হাতে 'Paid' করুন`],
      };
    }
  }
}

/** The email's explanation lines. */
function body(kind: AlertKind, ctx: MessageContext): string[] {
  switch (kind) {
    case "phoneSilent": {
      if (!ctx.lastSeenAt) throw new RangeError("lastSeenAt is required");
      const pending = count(ctx.pendingClaimCount ?? 0);
      return [
        `আপনার যাচাই ফোন ${
          dhakaTime(ctx.lastSeenAt)
        } থেকে BDPay-এর সাথে যোগাযোগ করেনি। ফোন সংযুক্ত না হওয়া পর্যন্ত নতুন পেমেন্ট নিশ্চিত হবে না।`,
        ...(pending > 0
          ? [`${pending} জন গ্রাহক পেমেন্ট নিশ্চিতের অপেক্ষায় আছেন।`]
          : []),
      ];
    }
    case "monitoringOff":
      return [
        "আপনার যাচাই ফোনে এসএমএস অনুমতি বা মনিটরিং বন্ধ আছে, তাই নতুন পেমেন্টের এসএমএস BDPay-তে আসছে না।",
      ];
    case "noActiveDevice":
      return [
        "আপনার Shopify স্টোর যুক্ত আছে, কিন্তু কোনো যাচাই ফোন যুক্ত নেই। ফোন ছাড়া পেমেন্ট নিশ্চিত করা যাবে না।",
      ];
    case "shopifyReconnect":
      return [
        "BDPay আপনার Shopify স্টোরের সাথে আর সংযোগ করতে পারছে না। আবার যুক্ত না করা পর্যন্ত অর্ডার স্বয়ংক্রিয়ভাবে 'Paid' হবে না।",
      ];
    case "reviewWaiting":
      return [
        `${
          count(ctx.reviewWaitingCount)
        } টি পেমেন্টে পাঠানো টাকা অর্ডারের সাথে মেলেনি। গ্রাহকরা আপনার সিদ্ধান্তের অপেক্ষায় আছেন।`,
      ];
    case "syncFailed":
      return [
        `অর্ডার ${
          orderRef(ctx)
        }-এর পেমেন্ট BDPay-তে নিশ্চিত হয়েছে, কিন্তু Shopify-তে অর্ডারটি স্বয়ংক্রিয়ভাবে 'Paid' করা যায়নি।`,
      ];
  }
}

function compose(businessName: string, p: Parts): Email {
  const name = oneLine(businessName);
  if (name === "") throw new RangeError("businessName is required");
  const lines = [`${name},`, "", ...p.body];
  if (p.steps.length > 0) {
    lines.push("", "করণীয়:", ...p.steps.map((s) => `- ${s}`));
  }
  lines.push("", SIGNATURE);
  return { subject: SUBJECT_PREFIX + p.title, text: lines.join("\n") };
}

/** The email for an alert (first email, reminder or event). */
export function alertEmail(kind: AlertKind, ctx: MessageContext): Email {
  return compose(ctx.businessName, {
    ...head(kind, ctx),
    body: body(kind, ctx),
  });
}

/** The "fixed" email. Only phoneSilent has one. */
export function fixedEmail(kind: "phoneSilent", businessName: string): Email {
  if (kind !== "phoneSilent") throw new RangeError("no fixed email");
  return compose(businessName, {
    title: "যাচাই ফোন আবার সংযুক্ত হয়েছে",
    body: [
      "আপনার যাচাই ফোন আবার BDPay-এর সাথে যুক্ত হয়েছে। পেমেন্ট আবার স্বয়ংক্রিয়ভাবে নিশ্চিত হচ্ছে।",
    ],
    steps: [],
  });
}

/** alerts-list: title = the subject line without "BDPay: ", hint = the first step. */
export function alertTitleHint(
  kind: AlertKind,
  ctx: Omit<MessageContext, "businessName">,
): TitleHint {
  const h = head(kind, { ...ctx, businessName: "" });
  return { title: h.title, hint: h.steps[0] };
}
