// Spec 09 OrderNotifier: called AFTER a verification is recorded. A throwing notifier never changes the payment
// (spec 10 retries Shopify on its own). NoopNotifier does nothing.

import type { Logger } from "./http.ts";
import type { PaymentSession } from "./types.ts";

export interface OrderNotifier {
  onSessionVerified(session: PaymentSession): Promise<void>;
}

export class NoopNotifier implements OrderNotifier {
  onSessionVerified(_session: PaymentSession): Promise<void> {
    return Promise.resolve();
  }
}

/** Runs the notifier; an error is logged by code only (no payment details) and swallowed. */
export async function notifySafely(
  notifier: OrderNotifier,
  session: PaymentSession,
  log: Logger,
  fn: string,
  requestId: string,
): Promise<void> {
  try {
    await notifier.onSessionVerified(session);
  } catch {
    log({
      fn,
      requestId,
      code: "notifierFailed",
      merchantId: session.merchantId,
    });
  }
}
