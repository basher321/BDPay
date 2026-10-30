// Spec 09: store records -> the spec 07 Session JSON for the pay page (+ status rejected, spec 07a).

import type { Store } from "./store.ts";
import type {
  AccountType,
  Operator,
  PaymentClaim,
  PaymentSession,
  SessionStatus,
  Wallet,
} from "./types.ts";

export interface SessionJson {
  token: string;
  merchantName: string;
  orderRef: string;
  amountPoisha: number;
  expiresAt: string | null;
  status: SessionStatus;
  operators: {
    operator: Operator;
    walletNumber: string;
    accountType: AccountType;
  }[];
  attemptsLeft: number;
  returnUrl: string;
  deviceOnline: boolean;
  submittedOperator: Operator | null;
  submittedTrxId: string | null;
  verifiedAt: string | null;
}

/** A phone counts as online when seen in the last 10 minutes. */
export const DEVICE_ONLINE_MS = 10 * 60 * 1000;

/** One entry per operator: a merchant account first, else the oldest wallet (store order). */
export function operatorsFrom(wallets: Wallet[]): SessionJson["operators"] {
  const best = new Map<Operator, Wallet>();
  for (const w of wallets) {
    if (!w.isActive) continue;
    const cur = best.get(w.operator);
    if (
      cur === undefined ||
      (cur.accountType !== "merchant" && w.accountType === "merchant")
    ) {
      best.set(w.operator, w);
    }
  }
  const order: Operator[] = ["bkash", "nagad", "rocket", "upay"];
  return order.filter((o) => best.has(o)).map((o) => {
    const w = best.get(o)!;
    return {
      operator: o,
      walletNumber: w.walletNumber,
      accountType: w.accountType,
    };
  });
}

/**
 * The status the customer sees. An open session past its submit deadline shows as expired before the cron job
 * writes it (nothing is written here).
 */
export function visibleStatus(
  session: PaymentSession,
  nowMs: number,
): SessionStatus {
  return session.status === "open" && nowMs > Date.parse(session.submitDeadline)
    ? "expired"
    : session.status;
}

export function toSessionJson(input: {
  token: string;
  session: PaymentSession;
  merchantName: string;
  wallets: Wallet[];
  deviceOnline: boolean;
  activeClaim: PaymentClaim | null;
  nowMs: number;
}): SessionJson {
  const { session, activeClaim } = input;
  const status = visibleStatus(session, input.nowMs);
  const expiresAt = status === "open"
    ? session.submitDeadline
    : status === "pending"
    ? activeClaim?.matchDeadline ?? null
    : null;
  return {
    token: input.token,
    merchantName: input.merchantName,
    orderRef: session.orderRef,
    amountPoisha: session.amountPoisha,
    expiresAt,
    status,
    operators: operatorsFrom(input.wallets),
    attemptsLeft: session.attemptsLeft,
    returnUrl: session.returnUrl,
    deviceOnline: input.deviceOnline,
    submittedOperator: activeClaim?.operator ?? null,
    submittedTrxId: activeClaim?.trxId ?? null,
    verifiedAt: session.verifiedAt,
  };
}

/** Reads what the view needs and builds it. */
export async function loadSessionJson(
  store: Store,
  token: string,
  session: PaymentSession,
  nowMs: number,
): Promise<SessionJson> {
  const [merchantName, wallets, deviceOnline, activeClaim] = await Promise.all([
    store.getMerchantName(session.merchantId),
    store.listActiveWallets(session.merchantId),
    store.hasDeviceSeenSince(
      session.merchantId,
      new Date(nowMs - DEVICE_ONLINE_MS).toISOString(),
    ),
    session.activeClaimId === null
      ? Promise.resolve(null)
      : store.getClaim(session.activeClaimId),
  ]);
  return toSessionJson({
    token,
    session,
    merchantName,
    wallets,
    deviceOnline,
    activeClaim,
    nowMs,
  });
}
