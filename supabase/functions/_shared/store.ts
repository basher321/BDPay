// Spec 08 Store interface. Edge Function logic talks only to this (CLAUDE.md Backend rules); spec 12 builds the
// tables and the real Postgres Store from this list. Every merchant-owned record carries merchantId.

import type {
  AuditEntry,
  Device,
  Match,
  MatchMethod,
  Operator,
  PaymentClaim,
  PaymentSession,
  SmsRecord,
  Wallet,
} from "./types.ts";

/** An unexpected store failure. The code is short and fixed; it never carries row contents (spec 12a). */
export type StoreErrorCode = "notFound" | "conflict" | "db";

export class StoreError extends Error {
  constructor(readonly code: StoreErrorCode) {
    super(`store: ${code}`);
    this.name = "StoreError";
  }
}

export interface ParserRulesRow {
  version: number;
  /** The rules file's JSON array, as stored. parser.loadRules compiles it. */
  rules: unknown;
}

export type NewDevice = Omit<Device, "id" | "createdAt">;
export type DeviceUpdate = Partial<
  Pick<
    Device,
    | "name"
    | "publicKeySpki"
    | "status"
    | "appVersion"
    | "androidVersion"
    | "lastSeenAt"
  >
>;

export interface Store {
  /** The merchant the user owns, or null. */
  findMerchantForUser(userId: string): Promise<{ merchantId: string } | null>;
  countActiveDevices(merchantId: string): Promise<number>;
  findDeviceByInstall(
    merchantId: string,
    installId: string,
  ): Promise<Device | null>;
  createDevice(fields: NewDevice): Promise<Device>;
  updateDevice(deviceId: string, fields: DeviceUpdate): Promise<Device>;
  getDevice(deviceId: string): Promise<Device | null>;
  getParserRules(): Promise<ParserRulesRow>;
  listActiveWallets(merchantId: string): Promise<Wallet[]>;
  findSmsByDedupe(
    merchantId: string,
    dedupeHash: string,
  ): Promise<SmsRecord | null>;
  /**
   * If the same merchantId + dedupeHash exists, returns the existing row with created false.
   * Must be safe when two requests race.
   */
  insertSms(
    record: Omit<SmsRecord, "id">,
  ): Promise<{ sms: SmsRecord; created: boolean }>;
  writeAudit(entry: AuditEntry): Promise<void>;

  // ---- Spec 09 ----
  createPaymentSession(fields: NewPaymentSession): Promise<PaymentSession>;
  getSessionByTokenHash(tokenHash: string): Promise<PaymentSession | null>;
  getSession(id: string): Promise<PaymentSession | null>;
  getClaim(id: string): Promise<PaymentClaim | null>;
  getSms(id: string): Promise<SmsRecord | null>;
  getMerchantName(merchantId: string): Promise<string>;
  /** Any active device of the merchant seen at or after [sinceIso]. */
  hasDeviceSeenSince(merchantId: string, sinceIso: string): Promise<boolean>;
  /** A claim with status pending, verified or mismatch for this merchant + operator + TrxID. */
  findLiveClaimByTrx(
    merchantId: string,
    operator: Operator,
    trxId: string,
  ): Promise<PaymentClaim | null>;
  /** One atomic decrement, never below 0 (plan 09 D27). Returns attemptsLeft after it. */
  spendAttempt(sessionId: string): Promise<number>;
  /**
   * ONE transaction: supersede the session's active pending claim, create the new claim (match deadline
   * now + 24 h), attemptsLeft - 1, session pending with activeClaimId. Any failed check -> conflict, nothing changed.
   */
  submitClaim(input: {
    sessionId: string;
    operator: Operator;
    trxId: string;
  }): Promise<{ claim: PaymentClaim } | { conflict: ClaimConflict }>;
  findUnmatchedSms(
    merchantId: string,
    operator: Operator,
    trxId: string,
  ): Promise<SmsRecord | null>;
  findPendingClaimByTrx(
    merchantId: string,
    operator: Operator,
    trxId: string,
  ): Promise<PaymentClaim | null>;
  /** ONE transaction: match + claim verified + session verified + SMS matched; anything taken -> conflict. */
  recordVerified(input: {
    claimId: string;
    smsId: string;
    method: MatchMethod;
    userId: string | null;
    note: string | null;
  }): Promise<"ok" | "conflict">;
  /** Guarded (plan 09 D33): only the session's active pending claim, with an unmatched SMS. */
  recordMismatch(input: {
    claimId: string;
    smsId: string;
    reason: string;
  }): Promise<"ok" | "conflict">;
  /** Guarded (plan 09 D33): only an active mismatch claim. */
  recordRejected(input: {
    claimId: string;
    userId: string;
    note: string | null;
  }): Promise<"ok" | "conflict">;
  /** The mismatch claim whose candidate is this SMS (the active one), or null. */
  findMismatchClaimBySms(smsId: string): Promise<PaymentClaim | null>;
  /** One entry per id of this merchant (other merchants' ids are left out). */
  getSmsResults(merchantId: string, smsIds: string[]): Promise<SmsResult[]>;
  expireDue(nowIso: string): Promise<{ sessions: number; claims: number }>;
  /** One atomic hit per window; true = allowed. */
  hitRateLimit(
    key: string,
    limit: number,
    windowSeconds: number,
  ): Promise<boolean>;
}

export interface NewPaymentSession {
  merchantId: string;
  storeId: string;
  tokenHash: string;
  orderRef: string;
  externalOrderId: string | null;
  amountPoisha: number;
  returnUrl: string;
  submitDeadline: string;
}

export type ClaimConflict = "alreadyUsed" | "noAttemptsLeft" | "closed";

/** sms-status input: the SMS, the claim tied to it (matched or candidate), its session and match. */
export interface SmsResult {
  sms: SmsRecord;
  claim: PaymentClaim | null;
  session: PaymentSession | null;
  match: Match | null;
}
