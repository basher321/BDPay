import assert from "node:assert/strict";
import {
  evaluateOrder,
  ORDER_QUERY,
  type ShopifyOrder,
} from "../_shared/shopify_orders.ts";

const order = (over: Partial<ShopifyOrder> = {}): ShopifyOrder => ({
  id: "gid://shopify/Order/1045",
  name: "#1045",
  displayFinancialStatus: "PENDING",
  paymentGatewayNames: ["BDPay (bKash / Nagad / Rocket / Upay)"],
  cancelledAt: null,
  statusPageUrl: "https://shop-a.myshopify.com/1/orders/abc/authenticate?key=k",
  totalOutstandingSet: {
    shopMoney: { amount: "1250.00", currencyCode: "BDT" },
  },
  ...over,
});

Deno.test("allowed: session fields from the order", () => {
  assert.deepEqual(evaluateOrder(order()), {
    allowed: true,
    fields: {
      orderRef: "#1045",
      externalOrderId: "gid://shopify/Order/1045",
      amountPoisha: 125000,
      returnUrl: "https://shop-a.myshopify.com/1/orders/abc/authenticate?key=k",
    },
  });
});

Deno.test("bdpay gateway match is case-insensitive and may be one of many", () => {
  assert.equal(
    evaluateOrder(order({ paymentGatewayNames: ["gift_card", "bdpay"] }))
      .allowed,
    true,
  );
  assert.equal(
    evaluateOrder(order({ paymentGatewayNames: ["Pay with BDPAY"] })).allowed,
    true,
  );
});

Deno.test("each reason", () => {
  const cases: [Partial<ShopifyOrder>, string][] = [
    [{ paymentGatewayNames: ["shopify_payments"] }, "notBdpay"],
    [{ paymentGatewayNames: [] }, "notBdpay"],
    [{ cancelledAt: "2026-10-29T06:00:00Z" }, "cancelled"],
    [{ displayFinancialStatus: "PAID" }, "alreadyPaid"],
    [{ displayFinancialStatus: "PARTIALLY_PAID" }, "alreadyPaid"],
    [{ displayFinancialStatus: null }, "alreadyPaid"],
    [{
      totalOutstandingSet: {
        shopMoney: { amount: "12.50", currencyCode: "USD" },
      },
    }, "wrongCurrency"],
    [{
      totalOutstandingSet: {
        shopMoney: { amount: "0.00", currencyCode: "BDT" },
      },
    }, "zeroAmount"],
    [{
      totalOutstandingSet: { shopMoney: { amount: "-5", currencyCode: "BDT" } },
    }, "zeroAmount"],
  ];
  for (const [over, reason] of cases) {
    assert.deepEqual(
      evaluateOrder(order(over)),
      { allowed: false, reason },
      reason,
    );
  }
});

Deno.test("rules are checked in the spec's order", () => {
  // A card order that is also cancelled and in USD -> notBdpay first.
  assert.deepEqual(
    evaluateOrder(order({
      paymentGatewayNames: ["shopify_payments"],
      cancelledAt: "2026-10-29T06:00:00Z",
      totalOutstandingSet: { shopMoney: { amount: "1", currencyCode: "USD" } },
    })),
    { allowed: false, reason: "notBdpay" },
  );
});

Deno.test("the query reads only the listed order fields (no customer data)", () => {
  for (
    const f of [
      "id",
      "name",
      "displayFinancialStatus",
      "paymentGatewayNames",
      "cancelledAt",
      "statusPageUrl",
      "totalOutstandingSet",
    ]
  ) {
    assert.ok(ORDER_QUERY.includes(f), f);
  }
  for (const f of ["customer", "email", "phone", "address", "billing"]) {
    assert.ok(!ORDER_QUERY.toLowerCase().includes(f.toLowerCase()), f);
  }
});
