// Spec 09 test helper: a FakeStore world with wallets, a merchant name, the real matcher, a recording notifier
// and the pay-session settings. Fake values only.

import { dedupeHash } from "../../_shared/parser.ts";
import { StoreMatcher } from "../../_shared/matcher.ts";
import type { OrderNotifier } from "../../_shared/notifier.ts";
import { storeLimiter } from "../../_shared/rate_limit.ts";
import { hashToken, newSessionToken } from "../../_shared/token.ts";
import type {
  Operator,
  PaymentSession,
  SmsRecord,
} from "../../_shared/types.ts";
import { addDevice, MIN, T0, world } from "./world.ts";

export const ORIGIN = "https://pay.example.com";
export const CRON = "test-cron-secret-not-real";

export class RecordingNotifier implements OrderNotifier {
  readonly verified: string[] = [];
  throws = false;
  onSessionVerified(session: PaymentSession): Promise<void> {
    this.verified.push(session.id);
    return this.throws
      ? Promise.reject(new Error("shopify down"))
      : Promise.resolve();
  }
}

export async function payWorld() {
  const w = world();
  const notifier = new RecordingNotifier();
  w.deps.notifier = notifier;
  w.deps.matcher = new StoreMatcher(w.store, notifier, w.deps.log);
  w.deps.limiter = storeLimiter(w.store);
  w.deps.config = {
    payPageOrigin: ORIGIN,
    cronSecret: CRON,
    rateLimitPepper: "pepper-not-real",
  };
  w.store.setMerchantName("m1", "নমুনা স্টোর");
  w.store.addWallet({
    id: "w-bkash",
    merchantId: "m1",
    operator: "bkash",
    walletNumber: "01700000001",
    accountType: "merchant",
    simSlot: "sim1",
    isActive: true,
  });
  w.store.addWallet({
    id: "w-rocket",
    merchantId: "m1",
    operator: "rocket",
    walletNumber: "017000000031",
    accountType: "agent",
    simSlot: "sim2",
    isActive: true,
  });
  const { device, key } = await addDevice(w.store);
  return { ...w, notifier, device, key };
}

type World = Awaited<ReturnType<typeof payWorld>>;

export async function newSession(
  w: World,
  over: { amountPoisha?: number; merchantId?: string } = {},
): Promise<{ token: string; session: PaymentSession }> {
  const token = newSessionToken();
  const session = await w.store.createPaymentSession({
    merchantId: over.merchantId ?? "m1",
    storeId: "store-1",
    tokenHash: await hashToken(token),
    orderRef: "#1045",
    externalOrderId: null,
    amountPoisha: over.amountPoisha ?? 125000,
    returnUrl: "https://shop.example.com/orders/1045",
    submitDeadline: new Date(w.clock.now + 60 * MIN).toISOString(),
  });
  return { token, session };
}

export async function addSms(
  w: World,
  trxId: string,
  over: Partial<SmsRecord> = {},
): Promise<SmsRecord> {
  const body = `You have received Tk ${trxId} TrxID ${trxId}`;
  const { sms } = await w.store.insertSms({
    merchantId: "m1",
    deviceId: w.device.id,
    walletId: "w-bkash",
    sender: "bKash",
    body,
    receivedAt: new Date(w.clock.now).toISOString(),
    serverReceivedAt: new Date(w.clock.now).toISOString(),
    simSlot: "sim1",
    dedupeHash: await dedupeHash("bKash", body + crypto.randomUUID()),
    operator: "bkash" as Operator,
    trxId,
    amountPoisha: 125000,
    payerNumber: "01700000009",
    status: "unmatched",
    rejectReason: null,
    parserVersion: 1,
    ...over,
  });
  return sms;
}

export const getReq = (token: string, origin?: string) =>
  new Request(`http://localhost/pay-session?t=${token}`, {
    headers: origin === undefined ? {} : { Origin: origin },
  });

export const postReq = (
  token: string,
  operator: string,
  trxId: string,
  ip = "203.0.113.5",
) =>
  new Request("http://localhost/pay-session", {
    method: "POST",
    headers: { "x-forwarded-for": ip, "content-type": "application/json" },
    body: JSON.stringify({ token, operator, trxId }),
  });

export { T0 };
