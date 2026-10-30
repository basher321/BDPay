// FakeShopify: an in-memory Shopify for tests and the local smoke script. Never used against real Shopify.
// It imitates the token rules that matter: single-use codes, refresh rotation (the old refresh token dies),
// expiring access tokens, and orders that live inside one shop only.
import type { ShopifyOrder } from "./shopify_orders.ts";
import {
  type GraphqlResult,
  type ShopifyClient,
  ShopifyError,
  type ShopifyErrorCode,
  type ShopifyTokens,
} from "./shopify_client.ts";

interface Issued {
  shop: string;
  kind: "access" | "refresh";
  expiresAt: number;
}

/** One call, for assertions. Tokens and codes are never recorded. */
export interface FakeCall {
  method: "exchangeCode" | "refresh" | "graphql";
  shop: string;
  operation?: string;
}

export class FakeShopify implements ShopifyClient {
  readonly calls: FakeCall[] = [];
  readonly orders = new Map<
    string,
    Map<string, ShopifyOrder & { tags: string[] }>
  >();
  /** Errors to throw on the next calls, in order. */
  readonly failNext: ShopifyErrorCode[] = [];
  /** userErrors to return on the next mutation. */
  readonly userErrorsNext: { code: string }[][] = [];
  accessLifetimeMs = 60 * 60 * 1000;
  refreshLifetimeMs = 90 * 24 * 60 * 60 * 1000;

  readonly #codes = new Map<string, string>();
  readonly #issued = new Map<string, Issued>();
  #counter = 0;

  constructor(readonly now: () => number = () => Date.now()) {}

  /** Shopify would send this code to the callback after the merchant approves. */
  addCode(shop: string, code: string): void {
    this.#codes.set(code, shop);
  }

  addOrder(shop: string, order: ShopifyOrder): void {
    if (!this.orders.has(shop)) this.orders.set(shop, new Map());
    this.orders.get(shop)!.set(order.id, { ...order, tags: [] });
  }

  #fail(): void {
    const code = this.failNext.shift();
    if (code) throw new ShopifyError(code);
  }

  #issue(shop: string): ShopifyTokens {
    const n = ++this.#counter;
    const now = this.now();
    const access = `fake-access-${n}`;
    const refresh = `fake-refresh-${n}`;
    this.#issued.set(access, {
      shop,
      kind: "access",
      expiresAt: now + this.accessLifetimeMs,
    });
    this.#issued.set(refresh, {
      shop,
      kind: "refresh",
      expiresAt: now + this.refreshLifetimeMs,
    });
    return {
      accessToken: access,
      accessExpiresAt: new Date(now + this.accessLifetimeMs).toISOString(),
      refreshToken: refresh,
      refreshExpiresAt: new Date(now + this.refreshLifetimeMs).toISOString(),
    };
  }

  #valid(token: string, shop: string, kind: Issued["kind"]): boolean {
    const t = this.#issued.get(token);
    return !!t && t.shop === shop && t.kind === kind &&
      t.expiresAt > this.now();
  }

  exchangeCode(shop: string, code: string): Promise<ShopifyTokens> {
    this.calls.push({ method: "exchangeCode", shop });
    this.#fail();
    if (this.#codes.get(code) !== shop) {
      return Promise.reject(new ShopifyError("badRequest", 400));
    }
    this.#codes.delete(code); // single use
    return Promise.resolve(this.#issue(shop));
  }

  refresh(shop: string, refreshToken: string): Promise<ShopifyTokens> {
    this.calls.push({ method: "refresh", shop });
    this.#fail();
    if (!this.#valid(refreshToken, shop, "refresh")) {
      return Promise.reject(new ShopifyError("invalidGrant", 400));
    }
    this.#issued.delete(refreshToken); // rotation: the old refresh token stops working
    return Promise.resolve(this.#issue(shop));
  }

  graphql(
    shop: string,
    accessToken: string,
    query: string,
    variables: Record<string, unknown>,
  ): Promise<GraphqlResult> {
    const operation = query.includes("orderMarkAsPaid")
      ? "orderMarkAsPaid"
      : query.includes("tagsAdd")
      ? "tagsAdd"
      : "order";
    this.calls.push({ method: "graphql", shop, operation });
    this.#fail();
    if (!this.#valid(accessToken, shop, "access")) {
      return Promise.reject(new ShopifyError("unauthorized", 401));
    }
    const shopOrders = this.orders.get(shop) ?? new Map();
    if (operation === "order") {
      const o = shopOrders.get(String(variables.id));
      if (!o) return Promise.resolve({ data: { order: null }, errors: null });
      const { tags: _tags, ...order } = o;
      return Promise.resolve({ data: { order }, errors: null });
    }
    const id = String(
      (variables.input as { id?: unknown } | undefined)?.id ?? variables.id,
    );
    const userErrors = this.userErrorsNext.shift() ?? [];
    const o = shopOrders.get(id);
    if (userErrors.length === 0 && o) {
      if (operation === "orderMarkAsPaid") {
        o.displayFinancialStatus = "PAID";
        o.totalOutstandingSet = {
          shopMoney: {
            amount: "0.00",
            currencyCode: o.totalOutstandingSet.shopMoney.currencyCode,
          },
        };
      } else {
        o.tags.push(...((variables.tags as string[] | undefined) ?? []));
      }
    }
    return Promise.resolve({
      data: { [operation]: { userErrors } },
      errors: null,
    });
  }
}
