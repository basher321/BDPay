// Pure functions for the pay page (spec 07). No DOM, no network: Deno imports this file for tests.

const BANGLA_ZERO = 0x09e6;

/** Whole poisha -> "৳ 1,250.00". Same rules as the app: integers only, never negative. */
export function formatPoisha(poisha) {
  if (!Number.isSafeInteger(poisha) || poisha < 0) {
    throw new RangeError("poisha must be a whole, non-negative number");
  }
  const rest = poisha % 100;
  const taka = (poisha - rest) / 100; // exact: poisha - rest is a multiple of 100
  const grouped = String(taka).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `৳ ${grouped}.${String(rest).padStart(2, "0")}`;
}

/** Bangla digits -> English digits. */
export function toEnglishDigits(text) {
  let out = "";
  for (const ch of String(text)) {
    const c = ch.codePointAt(0);
    out += c >= BANGLA_ZERO && c <= BANGLA_ZERO + 9 ? String.fromCharCode(c - BANGLA_ZERO + 0x30) : ch;
  }
  return out;
}

/** Bangla digits -> English, all spaces removed, upper case: " 9k48 x7z2 " -> "9K48X7Z2". */
export function normalizeTrxId(text) {
  return toEnglishDigits(text ?? "").replace(/\s+/g, "").toUpperCase();
}

const TRX_RULES = {
  bkash: /^[A-Z0-9]{8,12}$/,
  nagad: /^[A-Z0-9]{8,12}$/,
  upay: /^[A-Z0-9]{8,12}$/,
  rocket: /^[0-9]{8,14}$/,
};

/** bkash / nagad / upay: 8-12 letters or digits; rocket: 8-14 digits only. Expects a normalized TrxID. */
export function isValidTrxId(operator, trx) {
  const rule = Object.hasOwn(TRX_RULES, operator) ? TRX_RULES[operator] : null;
  return rule !== null && typeof trx === "string" && rule.test(trx);
}

const pad2 = (n) => String(n).padStart(2, "0");

/** "mm:ss"; "hh:mm:ss" from 1 hour; "00:00" at 0 or less. Whole seconds, rounded up. */
export function formatCountdown(msLeft) {
  if (!(msLeft > 0)) return "00:00";
  const total = Math.ceil(msLeft / 1000);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return h > 0 ? `${pad2(h)}:${pad2(m)}:${pad2(s)}` : `${pad2(m)}:${pad2(s)}`;
}

/** 3 s for the first 2 minutes after a claim, then 10 s. */
export function nextPollDelay(msSinceSubmit) {
  return msSinceSubmit < 120000 ? 3000 : 10000;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DHAKA_OFFSET_MS = 6 * 60 * 60 * 1000; // Asia/Dhaka is a fixed UTC+6, like the app

/** ISO UTC -> "29 Oct 2026, 06:25 PM" in Asia/Dhaka (the app's detail format). "" when not a date. */
export function formatDhakaTime(isoUtc) {
  const t = Date.parse(isoUtc);
  if (Number.isNaN(t)) return "";
  const d = new Date(t + DHAKA_OFFSET_MS);
  const h24 = d.getUTCHours();
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  const ampm = h24 < 12 ? "AM" : "PM";
  return `${pad2(d.getUTCDate())} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}, ${pad2(h12)}:${pad2(d.getUTCMinutes())} ${ampm}`;
}

/** Only https:, or http on localhost / 127.0.0.1 (local testing). Blocks javascript:, data: and the rest. */
export function isSafeReturnUrl(url) {
  if (typeof url !== "string" || url === "") return false;
  let u;
  try {
    u = new URL(url);
  } catch {
    return false;
  }
  if (u.protocol === "https:") return true;
  return u.protocol === "http:" && (u.hostname === "localhost" || u.hostname === "127.0.0.1");
}

export class TimeoutError extends Error {
  constructor() {
    super("timeout");
    this.name = "TimeoutError";
  }
}

/** Resolves like [promise], or rejects with TimeoutError after [ms]. */
export function withTimeout(promise, ms) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new TimeoutError()), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
