// Spec 17 tests: store-connections, merchant-api, the webhook notifier and store-webhooks-sync (FakeStore only).

import assert from "node:assert/strict";
import {
  hmacHex,
  orderPayToken,
  webhookSecret,
} from "../_shared/connections.ts";
import { handle as connections } from "../_shared/store_connections.ts";
import { handle as merchantApi } from "../_shared/merchant_api.ts";
import { handle as paySession } from "../_shared/pay_session.ts";
import { makeHandler } from "../_shared/store_webhooks_sync.ts";
import {
  MAX_ATTEMPTS,
  WebhookDelivery,
  WebhookNotifier,
  type WebhookSender,
} from "../_shared/webhook_notifier.ts";
import { MIN, USER_TOKEN, world } from "./helpers/world.ts";

const SECRET = "pay-token-secret-not-real";
const PAY_URL = "https://pay.example.com/";
const CRON = "cron-secret-not-real";
const BASE = "https://x.supabase.co/functions/v1";

function apiWorld() {
  const w = world();
  w.deps.config = {
    payTokenSecret: SECRET,
    payPageUrl: PAY_URL,
    payPageOrigin: "https://pay.example.com",
    cronSecret: CRON,
    rateLimitPepper: "pepper-not-real",
  };
  return w;
}
type W = ReturnType<typeof apiWorld>;

const connReq = (body?: unknown, token = USER_TOKEN) =>
  new Request(`${BASE}/store-connections`, {
    method: body === undefined ? "GET" : "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

async function create(w: W, over: Record<string, unknown> = {}) {
  const r = await connections(
    connReq({
      action: "create",
      platform: "laravel",
      siteName: "আমার দোকান",
      siteUrl: "https://shop.example.com/",
      ...over,
    }),
    w.deps,
  );
  return { status: r.status, body: await r.json() };
}

const apiReq = (
  key: string,
  method: "GET" | "POST",
  path: string,
  body?: unknown,
) =>
  new Request(`${BASE}/merchant-api${path}`, {
    method,
    headers: { Authorization: `Bearer ${key}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

const ORDER = {
  orderId: "WC-1001",
  orderRef: "#1001",
  amountPoisha: 125000,
  currency: "BDT",
  returnUrl: "https://shop.example.com/thanks/1001",
};

async function checkout(w: W, key: string, body: unknown = ORDER) {
  const r = await merchantApi(apiReq(key, "POST", "/checkouts", body), w.deps);
  return { status: r.status, body: await r.json() };
}

// ---- store-connections ----

Deno.test("create: returns the key and webhook secret once; only the hash is stored; audit", async () => {
  const w = apiWorld();
  const { status, body } = await create(w);
  assert.equal(status, 200);
  assert.match(body.apiKey, /^bdp_live_[A-Za-z0-9_-]{43}$/);
  assert.match(body.webhookSecret, /^whsec_/);
  assert.equal(body.connection.platform, "laravel");
  assert.equal(body.connection.kind, "api");
  assert.equal(body.connection.siteUrl, "https://shop.example.com");
  assert.equal(body.connection.apiKeyPrefix, body.apiKey.slice(0, 12));
  assert.equal("apiKeyHash" in body.connection, false);
  const stored = [...w.store.connections.values()][0];
  assert.notEqual(stored.apiKeyHash, body.apiKey);
  assert.equal(JSON.stringify(stored).includes(body.apiKey), false);
  assert.equal(w.store.audit.at(-1)?.action, "store.create");

  const list = await (await connections(connReq(), w.deps)).json();
  assert.equal(list.connections.length, 1);
  assert.equal(JSON.stringify(list).includes(body.apiKey), false);
});

Deno.test("create: shopify, bad platform, bad name, bad URL, duplicate", async () => {
  const w = apiWorld();
  assert.equal(
    (await create(w, { platform: "shopify" })).body.error,
    "useShopifyConnect",
  );
  assert.equal(
    (await create(w, { platform: "daraz" })).body.error,
    "invalidPlatform",
  );
  assert.equal((await create(w, { siteName: "a" })).body.error, "invalidName");
  for (
    const url of [
      "http://shop.example.com",
      "https://localhost",
      "https://10.0.0.1",
      "nope",
    ]
  ) {
    assert.equal(
      (await create(w, { siteUrl: url })).body.error,
      "invalidUrl",
      url,
    );
  }
  assert.equal((await create(w)).status, 200);
  const dup = await create(w);
  assert.equal(dup.status, 409);
  assert.equal(dup.body.error, "duplicate");
  assert.equal((await create(w, { platform: "wordpress" })).status, 200);
});

Deno.test("store-connections: bad token 401; no merchant 403; another merchant's id 404", async () => {
  const w = apiWorld();
  assert.equal(
    (await connections(connReq(undefined, "bad"), w.deps)).status,
    401,
  );
  assert.equal(
    (await connections(connReq(undefined, "token-no-merchant"), w.deps)).status,
    403,
  );
  const mine = await create(w);
  const other = await connections(
    connReq(
      { action: "disable", id: mine.body.connection.id },
      "token-owner-m2",
    ),
    w.deps,
  );
  assert.equal(other.status, 404);
  const list =
    await (await connections(connReq(undefined, "token-owner-m2"), w.deps))
      .json();
  assert.deepEqual(list.connections, []);
});

Deno.test("updateWebhook (https only, clearable), rotateKey and disable", async () => {
  const w = apiWorld();
  const c = (await create(w)).body;
  const id = c.connection.id;
  const bad = await connections(
    connReq({
      action: "updateWebhook",
      id,
      webhookUrl: "http://x.example.com",
    }),
    w.deps,
  );
  assert.equal(bad.status, 400);
  const ok = await (await connections(
    connReq({
      action: "updateWebhook",
      id,
      webhookUrl: "https://shop.example.com/bdpay-hook",
    }),
    w.deps,
  )).json();
  assert.equal(ok.connection.webhookUrl, "https://shop.example.com/bdpay-hook");
  const cleared = await (await connections(
    connReq({ action: "updateWebhook", id, webhookUrl: null }),
    w.deps,
  )).json();
  assert.equal(cleared.connection.webhookUrl, null);

  const rotated =
    await (await connections(connReq({ action: "rotateKey", id }), w.deps))
      .json();
  assert.notEqual(rotated.apiKey, c.apiKey);
  assert.equal((await checkout(w, c.apiKey)).status, 401);
  assert.equal((await checkout(w, rotated.apiKey)).status, 200);

  const off =
    await (await connections(connReq({ action: "disable", id }), w.deps))
      .json();
  assert.equal(off.connection.status, "disabled");
  assert.equal(
    (await checkout(w, rotated.apiKey, { ...ORDER, orderId: "WC-2" })).status,
    401,
  );
  // Disabling frees the site URL for a new connection.
  assert.equal((await create(w)).status, 200);
});

Deno.test("store-connections: no PAY_TOKEN_SECRET -> 503 (fails closed)", async () => {
  const w = apiWorld();
  w.deps.config = { ...w.deps.config, payTokenSecret: undefined };
  assert.equal((await create(w)).status, 503);
});

// ---- merchant-api ----

Deno.test("checkout: creates one session; the same order again gives the same pay link", async () => {
  const w = apiWorld();
  const { apiKey, connection } = (await create(w)).body;
  const a = await checkout(w, apiKey);
  assert.equal(a.status, 200);
  assert.equal(a.body.status, "open");
  const token = await orderPayToken(SECRET, connection.id, "WC-1001");
  assert.equal(a.body.payUrl, `${PAY_URL}?t=${token}`);
  const b = await checkout(w, apiKey);
  assert.equal(b.body.checkoutId, a.body.checkoutId);
  assert.equal(b.body.payUrl, a.body.payUrl);
  assert.equal(w.store.sessions.size, 1);
  const s = [...w.store.sessions.values()][0];
  assert.equal(s.amountPoisha, 125000);
  assert.equal(s.storeId, connection.id);
  assert.equal(
    s.submitDeadline,
    new Date(w.clock.now + 60 * MIN).toISOString(),
  );

  // The pay link opens the session through pay-session (spec 09).
  const view = await paySession(
    new Request(`https://x/pay-session?t=${token}`),
    w.deps,
  );
  assert.equal(view.status, 200);
  assert.equal((await view.json()).orderRef, "#1001");
});

Deno.test("checkout: orderChanged, wrongCurrency, badAmount, invalidUrl, badRequest", async () => {
  const w = apiWorld();
  const { apiKey } = (await create(w)).body;
  await checkout(w, apiKey);
  assert.equal(
    (await checkout(w, apiKey, { ...ORDER, amountPoisha: 99 })).body.error,
    "orderChanged",
  );
  assert.equal(
    (await checkout(w, apiKey, { ...ORDER, orderId: "2", currency: "USD" }))
      .body.error,
    "wrongCurrency",
  );
  for (const amount of [1250.5, "125000", 0, -5]) {
    assert.equal(
      (await checkout(w, apiKey, {
        ...ORDER,
        orderId: "3",
        amountPoisha: amount,
      })).body.error,
      "badAmount",
      String(amount),
    );
  }
  assert.equal(
    (await checkout(w, apiKey, {
      ...ORDER,
      orderId: "4",
      returnUrl: "http://a.b",
    })).body.error,
    "invalidUrl",
  );
  assert.equal(
    (await checkout(w, apiKey, { ...ORDER, orderId: "" })).body.error,
    "badRequest",
  );
});

Deno.test("merchant-api: missing / wrong key 401; GET status; unknown order 404; rate limit", async () => {
  const w = apiWorld();
  const { apiKey } = (await create(w)).body;
  assert.equal((await checkout(w, "")).status, 401);
  assert.equal((await checkout(w, "bdp_live_" + "x".repeat(43))).status, 401);
  const made = await checkout(w, apiKey);
  const got = await merchantApi(
    apiReq(apiKey, "GET", "/checkouts/WC-1001"),
    w.deps,
  );
  const body = await got.json();
  assert.equal(body.checkoutId, made.body.checkoutId);
  assert.equal(body.amountPoisha, 125000);
  assert.equal(body.status, "open");
  w.clock.now += 61 * MIN;
  const late = await (await merchantApi(
    apiReq(apiKey, "GET", "/checkouts/WC-1001"),
    w.deps,
  )).json();
  assert.equal(late.status, "expired");
  assert.equal(
    (await merchantApi(apiReq(apiKey, "GET", "/checkouts/nope"), w.deps))
      .status,
    404,
  );
  let last = 200;
  for (let i = 0; i < 61; i++) {
    last =
      (await merchantApi(apiReq(apiKey, "GET", "/checkouts/WC-1001"), w.deps))
        .status;
  }
  assert.equal(last, 429);
});

Deno.test("merchant-api: another merchant's key cannot see this merchant's order", async () => {
  const w = apiWorld();
  const mine = (await create(w)).body;
  await checkout(w, mine.apiKey);
  const r = await connections(
    connReq({
      action: "create",
      platform: "django",
      siteName: "Other",
      siteUrl: "https://other.example.com",
    }, "token-owner-m2"),
    w.deps,
  );
  const theirs = await r.json();
  assert.equal(
    (await merchantApi(
      apiReq(theirs.apiKey, "GET", "/checkouts/WC-1001"),
      w.deps,
    )).status,
    404,
  );
});

// ---- webhooks ----

function recorder(statuses: (number | null)[]) {
  const calls: {
    url: string;
    body: string;
    headers: Record<string, string>;
  }[] = [];
  const send: WebhookSender = (url, body, headers) => {
    calls.push({ url, body, headers });
    return Promise.resolve(
      statuses.length > 1 ? statuses.shift()! : statuses[0],
    );
  };
  return { calls, send };
}

async function verifiedSession(w: W, webhook: string | null) {
  const c = (await create(w)).body;
  if (webhook !== null) {
    await connections(
      connReq({
        action: "updateWebhook",
        id: c.connection.id,
        webhookUrl: webhook,
      }),
      w.deps,
    );
  }
  await checkout(w, c.apiKey);
  const s = [...w.store.sessions.values()][0];
  s.status = "verified";
  s.verifiedAt = new Date(w.clock.now).toISOString();
  return { c, session: { ...s } };
}

Deno.test("webhook: signed POST with the event; 2xx -> done; the site can check the signature", async () => {
  const w = apiWorld();
  const { c, session } = await verifiedSession(
    w,
    "https://shop.example.com/hook",
  );
  const rec = recorder([200]);
  const n = new WebhookNotifier(
    w.store,
    new WebhookDelivery(w.store, rec.send, SECRET, w.deps.now),
    w.deps.log,
  );
  await n.onSessionVerified(session);
  assert.equal(rec.calls.length, 1);
  const call = rec.calls[0];
  assert.equal(call.url, "https://shop.example.com/hook");
  const event = JSON.parse(call.body);
  assert.deepEqual(event, {
    event: "payment.verified",
    checkoutId: session.id,
    orderId: "WC-1001",
    orderRef: "#1001",
    amountPoisha: 125000,
    verifiedAt: session.verifiedAt,
  });
  const ts = call.headers["X-BDPay-Timestamp"];
  assert.equal(
    call.headers["X-BDPay-Signature"],
    await hmacHex(c.webhookSecret, `${ts}.${call.body}`),
  );
  assert.equal(
    c.webhookSecret,
    await webhookSecret(SECRET, c.connection.id, 1),
  );
  const sync = [...w.store.orderSyncs.values()][0];
  assert.equal(sync.status, "done");
  // Verified again (e.g. a second notifier call) -> no second send.
  await n.onSessionVerified(session);
  assert.equal(rec.calls.length, 1);
});

Deno.test("webhook: no webhook URL -> nothing sent; failure -> pending with the spec 10 wait", async () => {
  const w = apiWorld();
  const none = await verifiedSession(w, null);
  const rec = recorder([503]);
  const delivery = new WebhookDelivery(w.store, rec.send, SECRET, w.deps.now);
  await new WebhookNotifier(w.store, delivery, w.deps.log).onSessionVerified(
    none.session,
  );
  assert.equal(rec.calls.length, 0);

  const w2 = apiWorld();
  const { session } = await verifiedSession(
    w2,
    "https://shop.example.com/hook",
  );
  const d2 = new WebhookDelivery(w2.store, rec.send, SECRET, w2.deps.now);
  await new WebhookNotifier(w2.store, d2, w2.deps.log).onSessionVerified(
    session,
  );
  const sync = [...w2.store.orderSyncs.values()][0];
  assert.equal(sync.status, "pending");
  assert.equal(sync.attempts, 1);
  assert.equal(sync.lastError, "http503");
  assert.equal(sync.nextAttemptAt, new Date(w2.clock.now + MIN).toISOString());
  // The payment result is untouched.
  assert.equal(w2.store.sessions.get(session.id)!.status, "verified");
});

Deno.test("store-webhooks-sync: wrong secret 401; retries due items; fails after 24 attempts", async () => {
  const w = apiWorld();
  const { session } = await verifiedSession(w, "https://shop.example.com/hook");
  const rec = recorder([null]);
  const sync = makeHandler(rec.send);
  const call = (secret: string) =>
    sync(
      new Request(`${BASE}/store-webhooks-sync`, {
        method: "POST",
        headers: { "X-Cron-Secret": secret },
      }),
      w.deps,
    );
  assert.equal((await call("wrong")).status, 401);
  await w.store.enqueueOrderSync("m1", session.id);
  for (let i = 1; i <= MAX_ATTEMPTS; i++) {
    const r = await (await call(CRON)).json();
    assert.equal(r.done + r.retried + r.failed, 1, `attempt ${i}`);
    // Nothing is due until the wait has passed.
    assert.equal((await (await call(CRON)).json()).retried, 0);
    w.clock.now += 61 * MIN;
  }
  const s = [...w.store.orderSyncs.values()][0];
  assert.equal(s.status, "failed");
  assert.equal(s.attempts, MAX_ATTEMPTS);
  assert.equal(rec.calls.length, MAX_ATTEMPTS);
  assert.equal(w.store.sessions.get(session.id)!.status, "verified");
});
