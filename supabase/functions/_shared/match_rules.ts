// Spec 09 match rules: pure functions, no I/O, no logging.
// The input types below hold only the fields the rules read. They are local on purpose: spec 08's types.ts does
// not exist yet, so this file depends on nothing else. When spec 08 lands, its records are passed in as they are
// (they have these fields).

export type Operator = "bkash" | "nagad" | "rocket" | "upay";
export type SmsStatus = "received" | "unmatched" | "matched" | "rejected";

/** Times are ISO 8601 UTC strings; money is whole poisha. */
export interface MatchSession {
  merchantId: string;
  amountPoisha: number;
  createdAt: string;
}

export interface MatchClaim {
  merchantId: string;
  operator: Operator;
  trxId: string;
  matchDeadline: string;
}

export interface MatchSms {
  merchantId: string;
  operator: Operator;
  trxId: string;
  amountPoisha: number;
  status: SmsStatus;
  receivedAt: string;
}

/** Which candidate rule failed (rules 1-6), or "amount" for a mismatch. */
export type MatchReason =
  | "merchant"
  | "operator"
  | "trxId"
  | "smsStatus"
  | "tooEarly"
  | "tooLate"
  | "amount";

export type MatchResult =
  | { result: "verified"; reason: null }
  | { result: "mismatch"; reason: "amount" }
  | { result: "noMatch"; reason: Exclude<MatchReason, "amount"> };

/** An SMS may be at most this long before the session was created (rule 5). */
export const EARLY_WINDOW_MS = 30 * 60 * 1000;

function time(iso: string): number {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) throw new RangeError("invalid time");
  return t;
}

function poisha(value: number): number {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError("money must be whole, non-negative poisha");
  }
  return value;
}

/** Trimmed and upper case, as TrxIDs are stored. */
export function canonicalTrxId(trxId: string): string {
  return trxId.trim().toUpperCase();
}

/** Rule 1: SMS, claim and session belong to the same merchant. */
export function sameMerchant(
  session: MatchSession,
  claim: MatchClaim,
  sms: MatchSms,
): boolean {
  return sms.merchantId === claim.merchantId &&
    claim.merchantId === session.merchantId;
}

/** Rule 2: same operator. */
export function sameOperator(claim: MatchClaim, sms: MatchSms): boolean {
  return sms.operator === claim.operator;
}

/** Rule 3: same TrxID (both trimmed, upper case). */
export function sameTrxId(claim: MatchClaim, sms: MatchSms): boolean {
  const a = canonicalTrxId(claim.trxId);
  return a !== "" && a === canonicalTrxId(sms.trxId);
}

/** Rule 4: the SMS has not paid anything yet. */
export function smsUnmatched(sms: MatchSms): boolean {
  return sms.status === "unmatched";
}

/** Rule 5: received no earlier than 30 minutes before the session was created (exactly 30 minutes is fine). */
export function notTooEarly(session: MatchSession, sms: MatchSms): boolean {
  return time(sms.receivedAt) >= time(session.createdAt) - EARLY_WINDOW_MS;
}

/** Rule 6: received no later than the claim's match deadline. */
export function notTooLate(claim: MatchClaim, sms: MatchSms): boolean {
  return time(sms.receivedAt) <= time(claim.matchDeadline);
}

/**
 * Decides one SMS against one claim. Not a candidate -> noMatch with the first failed rule (the claim stays
 * pending). A candidate with the same amount -> verified; a different amount -> mismatch, reason "amount".
 * Amounts are compared as whole poisha only.
 */
export function evaluate(
  session: MatchSession,
  claim: MatchClaim,
  sms: MatchSms,
): MatchResult {
  if (!sameMerchant(session, claim, sms)) {
    return { result: "noMatch", reason: "merchant" };
  }
  if (!sameOperator(claim, sms)) {
    return { result: "noMatch", reason: "operator" };
  }
  if (!sameTrxId(claim, sms)) return { result: "noMatch", reason: "trxId" };
  if (!smsUnmatched(sms)) return { result: "noMatch", reason: "smsStatus" };
  if (!notTooEarly(session, sms)) {
    return { result: "noMatch", reason: "tooEarly" };
  }
  if (!notTooLate(claim, sms)) return { result: "noMatch", reason: "tooLate" };
  return poisha(sms.amountPoisha) === poisha(session.amountPoisha)
    ? { result: "verified", reason: null }
    : { result: "mismatch", reason: "amount" };
}
