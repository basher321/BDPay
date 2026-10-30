// Spec 07 TrxID rules, copied from pay_page/logic.js (the Edge bundle cannot import files outside
// supabase/functions). tests/trx_format_test.ts checks both give the same answers.

import type { Operator } from "./types.ts";

const BANGLA_ZERO = 0x09e6;

/** Bangla digits -> English, all spaces removed, upper case: " ৯k48 x7z2 " -> "9K48X7Z2". */
export function normalizeTrxId(text: string): string {
  let out = "";
  for (const ch of text) {
    const c = ch.codePointAt(0)!;
    out += c >= BANGLA_ZERO && c <= BANGLA_ZERO + 9
      ? String.fromCharCode(c - BANGLA_ZERO + 0x30)
      : ch;
  }
  return out.replace(/\s+/g, "").toUpperCase();
}

const TRX_RULES: Record<Operator, RegExp> = {
  bkash: /^[A-Z0-9]{8,12}$/,
  nagad: /^[A-Z0-9]{8,12}$/,
  upay: /^[A-Z0-9]{8,12}$/,
  rocket: /^[0-9]{8,14}$/,
};

/** bkash / nagad / upay: 8-12 letters or digits; rocket: 8-14 digits. Expects a normalized TrxID. */
export function isValidTrxId(operator: Operator, trx: string): boolean {
  return Object.hasOwn(TRX_RULES, operator) && TRX_RULES[operator].test(trx);
}
