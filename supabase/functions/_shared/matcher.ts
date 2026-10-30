// Spec 08 Matcher interface. NoopMatcher keeps every stored SMS pending; spec 09 replaces it.

import type { SmsRecord, VerifyStatus } from "./types.ts";

export interface MatchOutcome {
  verifyStatus: VerifyStatus;
  serverMessage: string | null;
}

export interface Matcher {
  onSmsStored(sms: SmsRecord): Promise<MatchOutcome>;
}

export class NoopMatcher implements Matcher {
  onSmsStored(_sms: SmsRecord): Promise<MatchOutcome> {
    return Promise.resolve({ verifyStatus: "pending", serverMessage: null });
  }
}

// ---- Spec 09: the real matcher ----

import { evaluate } from "./match_rules.ts";
import { notifySafely, type OrderNotifier } from "./notifier.ts";
import type { Logger } from "./http.ts";
import type { Store } from "./store.ts";
import type { PaymentSession } from "./types.ts";

export const MSG_VERIFIED = "অর্ডারের সাথে মিলেছে";
export const MSG_VERIFIED_MANUAL = "ম্যানুয়ালি অনুমোদিত";
export const MSG_MISMATCH = "অর্ডারের টাকার সাথে মেলেনি";
export const MSG_REJECTED_BY_MERCHANT = "ম্যানুয়ালি বাতিল";

/**
 * Spec 09 contract 2: an SMS was stored as unmatched; look for a pending claim with the same merchant, operator
 * and TrxID and decide. A lost race (recordVerified conflict) reads the current state and reports it.
 */
export class StoreMatcher implements Matcher {
  constructor(
    private readonly store: Store,
    private readonly notifier: OrderNotifier,
    private readonly log: Logger,
  ) {}

  async onSmsStored(sms: SmsRecord): Promise<MatchOutcome> {
    if (
      sms.status !== "unmatched" || sms.operator === null || sms.trxId === null
    ) {
      return { verifyStatus: "rejected", serverMessage: null };
    }
    const claim = await this.store.findPendingClaimByTrx(
      sms.merchantId,
      sms.operator,
      sms.trxId,
    );
    if (claim === null) return { verifyStatus: "pending", serverMessage: null };
    const session = await this.store.getSession(claim.sessionId);
    if (session === null || sms.amountPoisha === null) {
      return { verifyStatus: "pending", serverMessage: null };
    }
    const decision = evaluate(session, claim, {
      merchantId: sms.merchantId,
      operator: sms.operator,
      trxId: sms.trxId,
      amountPoisha: sms.amountPoisha,
      status: sms.status,
      receivedAt: sms.receivedAt,
    });
    if (decision.result === "verified") {
      const r = await this.store.recordVerified({
        claimId: claim.id,
        smsId: sms.id,
        method: "auto",
        userId: null,
        note: null,
      });
      if (r === "ok") {
        await this.notify(session);
        return { verifyStatus: "verified", serverMessage: MSG_VERIFIED };
      }
      return await this.current(sms);
    }
    if (decision.result === "mismatch") {
      const r = await this.store.recordMismatch({
        claimId: claim.id,
        smsId: sms.id,
        reason: decision.reason,
      });
      return r === "ok"
        ? { verifyStatus: "mismatch", serverMessage: MSG_MISMATCH }
        : await this.current(sms);
    }
    return { verifyStatus: "pending", serverMessage: null };
  }

  private async notify(session: PaymentSession): Promise<void> {
    const fresh = await this.store.getSession(session.id);
    if (fresh !== null) {
      await notifySafely(this.notifier, fresh, this.log, "matcher", "matcher");
    }
  }

  /** After a lost race: what the SMS shows now. */
  private async current(sms: SmsRecord): Promise<MatchOutcome> {
    const [r] = await this.store.getSmsResults(sms.merchantId, [sms.id]);
    return r === undefined
      ? { verifyStatus: "pending", serverMessage: null }
      : smsOutcome(r);
  }
}

/** Spec 09 contract 4: the verify status and message an SMS shows (also used by sms-status). */
export function smsOutcome(r: {
  sms: SmsRecord;
  claim: { status: string } | null;
  match: { method: string } | null;
}): MatchOutcome {
  if (r.sms.status === "rejected") {
    return { verifyStatus: "rejected", serverMessage: null };
  }
  if (r.sms.status === "matched") {
    return {
      verifyStatus: "verified",
      serverMessage: r.match?.method === "manual"
        ? MSG_VERIFIED_MANUAL
        : MSG_VERIFIED,
    };
  }
  if (r.claim?.status === "mismatch") {
    return { verifyStatus: "mismatch", serverMessage: MSG_MISMATCH };
  }
  if (r.claim?.status === "rejected") {
    return {
      verifyStatus: "rejected",
      serverMessage: MSG_REJECTED_BY_MERCHANT,
    };
  }
  return { verifyStatus: "pending", serverMessage: null };
}
