// Spec 17 WebhookNotifier: after a payment of an API connection is verified, tell the merchant's website.
// The try is queued in order_syncs (one per session) and tried once at once; store-webhooks-sync retries.
// A webhook failure never changes the payment result. Bodies, URLs and secrets are never logged.

import { hmacHex, webhookSecret } from "./connections.ts";
import type { Logger } from "./http.ts";
import type { OrderNotifier } from "./notifier.ts";
import type { Store } from "./store.ts";
import type { OrderSync, PaymentSession } from "./types.ts";

/** Spec 10 retry waits in minutes after attempt 1, 2, 3, ...; then every 60 minutes. */
export const RETRY_WAITS_MIN = [1, 2, 5, 10, 30];
export const MAX_ATTEMPTS = 24;
export const SEND_TIMEOUT_MS = 10_000;

/** POSTs the body; returns the HTTP status, or null for no answer (network error or timeout). */
export type WebhookSender = (
  url: string,
  body: string,
  headers: Record<string, string>,
) => Promise<number | null>;

export const fetchSender: WebhookSender = async (url, body, headers) => {
  try {
    const r = await fetch(url, {
      method: "POST",
      body,
      headers: { "content-type": "application/json", ...headers },
      redirect: "manual",
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
    });
    await r.body?.cancel();
    return r.status;
  } catch {
    return null;
  }
};

export function nextWaitMs(attempts: number): number {
  return (RETRY_WAITS_MIN[attempts - 1] ?? 60) * 60_000;
}

export type SyncOutcome = "done" | "retried" | "failed";

export class WebhookDelivery {
  constructor(
    private readonly store: Store,
    private readonly send: WebhookSender,
    private readonly secret: string | undefined,
    private readonly now: () => number,
  ) {}

  /** One try of one queued sync; writes the result back. */
  async attempt(sync: OrderSync): Promise<SyncOutcome> {
    const session = await this.store.getSession(sync.sessionId);
    const conn = session === null
      ? null
      : await this.store.getConnection(session.storeId);
    const finish = async (
      status: "done" | "pending" | "failed",
      attempts: number,
      lastError: string | null,
    ): Promise<SyncOutcome> => {
      const waitMs = status === "pending" ? nextWaitMs(attempts) : 0;
      await this.store.updateOrderSync(sync.id, {
        status,
        attempts,
        nextAttemptAt: new Date(this.now() + waitMs).toISOString(),
        lastError,
      });
      return status === "pending" ? "retried" : status;
    };
    if (
      session === null || conn === null || conn.kind !== "api" ||
      conn.webhookUrl === null || !this.secret
    ) {
      return await finish("done", sync.attempts, "noWebhook");
    }

    const body = JSON.stringify({
      event: "payment.verified",
      checkoutId: session.id,
      orderId: session.externalOrderId,
      orderRef: session.orderRef,
      amountPoisha: session.amountPoisha,
      verifiedAt: session.verifiedAt,
    });
    const timestamp = String(Math.floor(this.now() / 1000));
    const key = await webhookSecret(this.secret, conn.id, conn.secretVersion);
    const status = await this.send(conn.webhookUrl, body, {
      "X-BDPay-Event-Id": sync.id,
      "X-BDPay-Timestamp": timestamp,
      "X-BDPay-Signature": await hmacHex(key, `${timestamp}.${body}`),
    });
    const attempts = sync.attempts + 1;
    if (status !== null && status >= 200 && status < 300) {
      return await finish("done", attempts, null);
    }
    const why = status === null ? "noAnswer" : `http${status}`;
    return await finish(
      attempts >= MAX_ATTEMPTS ? "failed" : "pending",
      attempts,
      why,
    );
  }
}

export class WebhookNotifier implements OrderNotifier {
  constructor(
    private readonly store: Store,
    private readonly delivery: WebhookDelivery,
    private readonly log: Logger,
  ) {}

  async onSessionVerified(session: PaymentSession): Promise<void> {
    const conn = await this.store.getConnection(session.storeId);
    if (conn === null || conn.kind !== "api" || conn.webhookUrl === null) {
      return; // Shopify (spec 10) or no webhook: the site reads GET /checkouts.
    }
    const sync = await this.store.enqueueOrderSync(
      session.merchantId,
      session.id,
    );
    if (sync.status !== "pending") return;
    const outcome = await this.delivery.attempt(sync);
    this.log({
      fn: "webhook-notifier",
      requestId: sync.id,
      code: `webhook:${outcome}`,
      merchantId: session.merchantId,
    });
  }
}
