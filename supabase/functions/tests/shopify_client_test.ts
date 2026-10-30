import assert from "node:assert/strict";
import {
  FetchShopifyClient,
  REFRESH_MARGIN_MS,
  ShopifyError,
  type ShopifyTokens,
  type TokenStore,
  withFreshToken,
} from "../_shared/shopify_client.ts";
import { FakeShopify } from "../_shared/fake_shopify.ts";
import { ORDER_QUERY } from "../_shared/shopify_orders.ts";

// Made-up test values only.
const KEY = "test-api-key-not-real";
const SECRET = "test-app-secret-not-real";
const SHOP = "shop-a.myshopify.com";
const NOW = Date.parse("2026-10-29T06:00:00Z");

// ---------- FetchShopifyClient with a recording fake fetch ----------

interface Seen {
  url: string;
  headers: Record<string, string>;
  body: Record<string, unknown>;
}

function fakeFetch(
  respond: (seen: Seen) => Response | Promise<Response>,
): { fetchFn: typeof fetch; seen: Seen[] } {
  const seen: Seen[] = [];
  const fetchFn = ((input: string | URL | Request, init?: RequestInit) => {
    const s: Seen = {
      url: String(input),
      headers: Object.fromEntries(new Headers(init?.headers).entries()),
      body: JSON.parse(String(init?.body ?? "{}")),
    };
    seen.push(s);
    return Promise.resolve(respond(s));
  }) as typeof fetch;
  return { fetchFn, seen };
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const tokenBody = {
  access_token: "shpat_test_access",
  expires_in: 3600,
  refresh_token: "shprt_test_refresh",
  refresh_token_expires_in: 7776000,
  scope: "read_orders,write_orders",
};

function client(respond: (s: Seen) => Response | Promise<Response>) {
  const f = fakeFetch(respond);
  return {
    seen: f.seen,
    c: new FetchShopifyClient({
      apiKey: KEY,
      apiSecret: SECRET,
      apiVersion: "2026-10",
      now: () => NOW,
      fetchFn: f.fetchFn,
    }),
  };
}

Deno.test("exchangeCode: POST to the shop's token endpoint with expiring=1", async () => {
  const { c, seen } = client(() => json(200, tokenBody));
  const t = await c.exchangeCode(SHOP, "test-code");
  assert.equal(seen[0].url, `https://${SHOP}/admin/oauth/access_token`);
  assert.deepEqual(seen[0].body, {
    client_id: KEY,
    client_secret: SECRET,
    code: "test-code",
    expiring: 1,
  });
  assert.deepEqual(t, {
    accessToken: "shpat_test_access",
    accessExpiresAt: new Date(NOW + 3600_000).toISOString(),
    refreshToken: "shprt_test_refresh",
    refreshExpiresAt: new Date(NOW + 7776000_000).toISOString(),
  });
});

Deno.test("refresh: grant_type refresh_token", async () => {
  const { c, seen } = client(() => json(200, tokenBody));
  await c.refresh(SHOP, "old-refresh");
  assert.equal(seen[0].body.grant_type, "refresh_token");
  assert.equal(seen[0].body.refresh_token, "old-refresh");
});

Deno.test("token endpoint errors map to fixed codes without the body", async () => {
  const cases: [Response, string][] = [
    [
      json(400, { error: "invalid_grant", error_description: "secret detail" }),
      "invalidGrant",
    ],
    [json(400, { error: "invalid_request" }), "badRequest"],
    [json(429, {}), "rateLimited"],
    [json(503, {}), "server"],
    [json(200, { access_token: "x" }), "badResponse"],
  ];
  for (const [res, code] of cases) {
    const { c } = client(() => res);
    await assert.rejects(c.refresh(SHOP, "r"), (e: unknown) => {
      assert.ok(e instanceof ShopifyError);
      assert.equal(e.code, code);
      assert.equal(e.message, code); // nothing from the body
      return true;
    });
  }
});

Deno.test("network failure -> network", async () => {
  const fetchFn = (() => Promise.reject(new TypeError("boom"))) as typeof fetch;
  const c = new FetchShopifyClient({
    apiKey: KEY,
    apiSecret: SECRET,
    apiVersion: "2026-10",
    fetchFn,
  });
  await assert.rejects(c.exchangeCode(SHOP, "c"), { code: "network" });
});

Deno.test("an invalid shop is refused before any request (no other host is ever called)", async () => {
  const { c, seen } = client(() => json(200, tokenBody));
  for (const shop of ["evil.com", "shop.myshopify.com.evil.com", "localhost"]) {
    await assert.rejects(c.exchangeCode(shop, "c"), { code: "invalidShop" });
    await assert.rejects(c.graphql(shop, "t", ORDER_QUERY, {}), {
      code: "invalidShop",
    });
  }
  assert.equal(seen.length, 0);
});

Deno.test("graphql: version in the URL, token only in the header, errors reduced to codes", async () => {
  const { c, seen } = client(() =>
    json(200, {
      data: { order: null },
      errors: [{ message: "secret text", extensions: { code: "NOT_FOUND" } }],
    })
  );
  const r = await c.graphql(SHOP, "shpat_test_access", ORDER_QUERY, {
    id: "gid://shopify/Order/1",
  });
  assert.equal(seen[0].url, `https://${SHOP}/admin/api/2026-10/graphql.json`);
  assert.equal(seen[0].headers["x-shopify-access-token"], "shpat_test_access");
  assert.ok(!seen[0].url.includes("shpat_test_access"));
  assert.deepEqual(r, {
    data: { order: null },
    errors: [{ code: "NOT_FOUND" }],
  });
});

Deno.test("graphql: 429, THROTTLED, 5xx, 401 -> fixed codes", async () => {
  const cases: [Response, string][] = [
    [json(429, {}), "rateLimited"],
    [
      json(200, { errors: [{ extensions: { code: "THROTTLED" } }] }),
      "rateLimited",
    ],
    [json(502, {}), "server"],
    [json(401, {}), "unauthorized"],
  ];
  for (const [res, code] of cases) {
    const { c } = client(() => res);
    await assert.rejects(c.graphql(SHOP, "t", ORDER_QUERY, {}), { code });
  }
});

// ---------- withFreshToken (5-minute rule + D39 compare-and-swap) ----------

class MemoryTokens implements TokenStore {
  tokens = new Map<string, ShopifyTokens>();
  lastError = new Map<string, string | null>();
  // deno-lint-ignore require-await
  async getShopifyTokens(id: string) {
    return this.tokens.get(id) ?? null;
  }
  // deno-lint-ignore require-await
  async swapShopifyTokens(id: string, oldRefresh: string, next: ShopifyTokens) {
    // one synchronous block: compare and write together
    if (this.tokens.get(id)?.refreshToken !== oldRefresh) {
      return "changed" as const;
    }
    this.tokens.set(id, next);
    return "ok" as const;
  }
  // deno-lint-ignore require-await
  async setStoreLastError(id: string, code: "reconnectNeeded" | null) {
    this.lastError.set(id, code);
  }
}

async function setup(accessLeftMs: number) {
  let now = NOW;
  const shopify = new FakeShopify(() => now);
  shopify.addCode(SHOP, "c1");
  const first = await shopify.exchangeCode(SHOP, "c1");
  const tokens = new MemoryTokens();
  // Move the clock so the access token has [accessLeftMs] left.
  now = Date.parse(first.accessExpiresAt) - accessLeftMs;
  tokens.tokens.set("st1", first);
  const deps = { tokens, client: shopify, now: () => now };
  return {
    shopify,
    tokens,
    deps,
    first,
    store: { id: "st1", shopDomain: SHOP },
  };
}

Deno.test("more than 5 minutes left -> no refresh", async () => {
  const { shopify, deps, first, store } = await setup(REFRESH_MARGIN_MS + 1000);
  assert.equal(await withFreshToken(deps, store), first.accessToken);
  assert.equal(shopify.calls.filter((c) => c.method === "refresh").length, 0);
});

Deno.test("under 5 minutes -> refresh first and save the new pair", async () => {
  const { shopify, tokens, deps, first, store } = await setup(4 * 60 * 1000);
  const access = await withFreshToken(deps, store);
  assert.notEqual(access, first.accessToken);
  assert.equal(tokens.tokens.get("st1")!.accessToken, access);
  assert.notEqual(tokens.tokens.get("st1")!.refreshToken, first.refreshToken);
  assert.equal(shopify.calls.filter((c) => c.method === "refresh").length, 1);
  // the old refresh token no longer works (rotation)
  await assert.rejects(shopify.refresh(SHOP, first.refreshToken), {
    code: "invalidGrant",
  });
});

Deno.test("invalid grant (nobody else refreshed) -> lastError reconnectNeeded", async () => {
  const { shopify, tokens, deps, store } = await setup(60 * 1000);
  shopify.failNext.push("invalidGrant");
  await assert.rejects(withFreshToken(deps, store), {
    code: "reconnectNeeded",
  });
  assert.equal(tokens.lastError.get("st1"), "reconnectNeeded");
});

Deno.test("D39: two refreshes at once -> both get the new token, no reconnectNeeded", async () => {
  const { tokens, deps, store } = await setup(60 * 1000);
  const [a, b] = await Promise.all([
    withFreshToken(deps, store),
    withFreshToken(deps, store),
  ]);
  assert.equal(a, b);
  assert.equal(a, tokens.tokens.get("st1")!.accessToken);
  assert.equal(tokens.lastError.get("st1"), undefined);
});

Deno.test("refresh fails for another reason but the token is still valid -> keep using it", async () => {
  const { shopify, deps, first, store } = await setup(60 * 1000);
  shopify.failNext.push("server");
  assert.equal(await withFreshToken(deps, store), first.accessToken);
});

Deno.test("refresh fails and the token has expired -> the error is thrown", async () => {
  const { shopify, deps, store } = await setup(-1000);
  shopify.failNext.push("network");
  await assert.rejects(withFreshToken(deps, store), { code: "network" });
});

Deno.test("no tokens -> reconnectNeeded", async () => {
  const { tokens, deps, store } = await setup(60 * 60 * 1000);
  tokens.tokens.clear();
  await assert.rejects(withFreshToken(deps, store), {
    code: "reconnectNeeded",
  });
});

// ---------- FakeShopify basics ----------

Deno.test("FakeShopify: single-use code; orders live inside one shop; mark paid + tags", async () => {
  const s = new FakeShopify(() => NOW);
  s.addCode(SHOP, "c1");
  const t = await s.exchangeCode(SHOP, "c1");
  await assert.rejects(s.exchangeCode(SHOP, "c1"), { code: "badRequest" });
  const order = {
    id: "gid://shopify/Order/1",
    name: "#1",
    displayFinancialStatus: "PENDING",
    paymentGatewayNames: ["bdpay"],
    cancelledAt: null,
    statusPageUrl: "https://shop-a.myshopify.com/s",
    totalOutstandingSet: {
      shopMoney: { amount: "10.00", currencyCode: "BDT" },
    },
  };
  s.addOrder(SHOP, order);
  const found = await s.graphql(SHOP, t.accessToken, ORDER_QUERY, {
    id: order.id,
  });
  assert.deepEqual((found.data as { order: unknown }).order, order);
  // the same id asked through another shop's token finds nothing of shop A
  s.addCode("shop-b.myshopify.com", "c2");
  const tb = await s.exchangeCode("shop-b.myshopify.com", "c2");
  const other = await s.graphql(
    "shop-b.myshopify.com",
    tb.accessToken,
    ORDER_QUERY,
    {
      id: order.id,
    },
  );
  assert.deepEqual(other.data, { order: null });
  // a token of shop B does not work on shop A
  await assert.rejects(s.graphql(SHOP, tb.accessToken, ORDER_QUERY, {}), {
    code: "unauthorized",
  });
  await s.graphql(SHOP, t.accessToken, "mutation { orderMarkAsPaid }", {
    input: { id: order.id },
  });
  await s.graphql(SHOP, t.accessToken, "mutation { tagsAdd }", {
    id: order.id,
    tags: ["BDPay-verified"],
  });
  const stored = s.orders.get(SHOP)!.get(order.id)!;
  assert.equal(stored.displayFinancialStatus, "PAID");
  assert.deepEqual(stored.tags, ["BDPay-verified"]);
  assert.equal(
    s.calls.filter((c) => c.operation === "orderMarkAsPaid").length,
    1,
  );
});
