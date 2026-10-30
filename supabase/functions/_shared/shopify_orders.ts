// Spec 10: Shopify order -> payment session rules. Pure: no I/O, no logging.
import { moneyTextToPoisha } from "./money_text.ts";

/** The only order fields BDPay reads (no customer data). */
export const ORDER_QUERY = `query BdpayOrder($id: ID!) {
  order(id: $id) {
    id
    name
    displayFinancialStatus
    paymentGatewayNames
    cancelledAt
    statusPageUrl
    totalOutstandingSet { shopMoney { amount currencyCode } }
  }
}`;

export interface ShopifyOrder {
  id: string;
  name: string;
  displayFinancialStatus: string | null;
  paymentGatewayNames: string[];
  cancelledAt: string | null;
  statusPageUrl: string;
  totalOutstandingSet: {
    shopMoney: { amount: string; currencyCode: string };
  };
}

export type OrderReason =
  | "notBdpay"
  | "cancelled"
  | "alreadyPaid"
  | "wrongCurrency"
  | "zeroAmount";

export interface SessionFields {
  orderRef: string;
  externalOrderId: string;
  amountPoisha: number;
  returnUrl: string;
}

export type OrderDecision =
  | { allowed: true; fields: SessionFields }
  | { allowed: false; reason: OrderReason };

/**
 * A session is created only when ALL hold: a "bdpay" gateway (case-insensitive), not cancelled, financial status
 * PENDING, currency BDT, outstanding amount > 0. Otherwise the first failing rule is the reason.
 * An outstanding amount that is not valid money text counts as zeroAmount (nothing to collect safely).
 */
export function evaluateOrder(order: ShopifyOrder): OrderDecision {
  const gateways = Array.isArray(order.paymentGatewayNames)
    ? order.paymentGatewayNames
    : [];
  if (
    !gateways.some((g) =>
      typeof g === "string" && g.toLowerCase().includes("bdpay")
    )
  ) {
    return { allowed: false, reason: "notBdpay" };
  }
  if (order.cancelledAt !== null) {
    return { allowed: false, reason: "cancelled" };
  }
  if (order.displayFinancialStatus !== "PENDING") {
    return { allowed: false, reason: "alreadyPaid" };
  }
  const money = order.totalOutstandingSet?.shopMoney;
  if (money?.currencyCode !== "BDT") {
    return { allowed: false, reason: "wrongCurrency" };
  }
  const amountPoisha = moneyTextToPoisha(money.amount);
  if (amountPoisha === null || amountPoisha <= 0) {
    return { allowed: false, reason: "zeroAmount" };
  }
  return {
    allowed: true,
    fields: {
      orderRef: order.name,
      externalOrderId: order.id,
      amountPoisha,
      returnUrl: order.statusPageUrl,
    },
  };
}
