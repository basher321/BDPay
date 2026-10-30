import assert from "node:assert/strict";
import {
  constantTimeEqual,
  isValidShopDomain,
  normalizeShopDomain,
  verifyOAuthQueryHmac,
  verifySessionToken,
  verifyWebhookHmac,
} from "../_shared/shopify_auth.ts";

// Made-up test values only. No real Shopify key or secret is used anywhere.
const SECRET = "test-app-secret-not-real";
const API_KEY = "test-api-key-not-real";
const NOW = Date.parse("2026-10-29T06:00:00Z");
const enc = new TextEncoder();

async function hmac(
  secret: string,
  data: Uint8Array<ArrayBuffer>,
): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, data));
}
const hex = (b: Uint8Array) =>
  [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
const b64url = (b: Uint8Array) =>
  b64(b).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const jsonPart = (v: unknown) => b64url(enc.encode(JSON.stringify(v)));

async function signedQuery(
  params: Record<string, string>,
  secret = SECRET,
): Promise<URLSearchParams> {
  const message = Object.keys(params).sort().map((k) => `${k}=${params[k]}`)
    .join("&");
  const q = new URLSearchParams(params);
  q.set("hmac", hex(await hmac(secret, enc.encode(message))));
  return q;
}

async function jwt(
  claims: Record<string, unknown>,
  header: Record<string, unknown> = { alg: "HS256", typ: "JWT" },
  secret = SECRET,
): Promise<string> {
  const head = `${jsonPart(header)}.${jsonPart(claims)}`;
  return `${head}.${b64url(await hmac(secret, enc.encode(head)))}`;
}

const goodClaims = () => ({
  iss: "https://shop-a.myshopify.com/admin",
  dest: "https://shop-a.myshopify.com",
  aud: API_KEY,
  sub: "gid://shopify/Customer/1",
  exp: NOW / 1000 + 60,
  nbf: NOW / 1000 - 5,
  iat: NOW / 1000 - 5,
  jti: "j1",
});
const check = { apiKey: API_KEY, secret: SECRET, now: NOW };

// ---------- OAuth query HMAC ----------

const oauthParams = {
  code: "test-code",
  shop: "shop-a.myshopify.com",
  state: "s1",
  timestamp: "1793253600",
};

Deno.test("OAuth HMAC: a correctly signed query passes", async () => {
  assert.equal(
    await verifyOAuthQueryHmac(await signedQuery(oauthParams), SECRET),
    true,
  );
});

Deno.test("OAuth HMAC: changed value, wrong secret, missing or bad hmac fail", async () => {
  const q = await signedQuery(oauthParams);
  const changed = new URLSearchParams(q);
  changed.set("shop", "shop-b.myshopify.com");
  assert.equal(await verifyOAuthQueryHmac(changed, SECRET), false);
  assert.equal(
    await verifyOAuthQueryHmac(await signedQuery(oauthParams, "other"), SECRET),
    false,
  );
  const missing = new URLSearchParams(q);
  missing.delete("hmac");
  assert.equal(await verifyOAuthQueryHmac(missing, SECRET), false);
  const upper = new URLSearchParams(q);
  upper.set("hmac", q.get("hmac")!.toUpperCase());
  assert.equal(await verifyOAuthQueryHmac(upper, SECRET), false);
  const short = new URLSearchParams(q);
  short.set("hmac", q.get("hmac")!.slice(0, 62));
  assert.equal(await verifyOAuthQueryHmac(short, SECRET), false);
  assert.equal(await verifyOAuthQueryHmac(q, ""), false);
});

Deno.test("OAuth HMAC: duplicate keys or two hmac values are refused", async () => {
  const q = await signedQuery(oauthParams);
  const dup = new URLSearchParams(q);
  dup.append("shop", "shop-a.myshopify.com");
  assert.equal(await verifyOAuthQueryHmac(dup, SECRET), false);
  const twoHmac = new URLSearchParams(q);
  twoHmac.append("hmac", q.get("hmac")!);
  assert.equal(await verifyOAuthQueryHmac(twoHmac, SECRET), false);
});

// ---------- Webhook HMAC ----------

const body = enc.encode(
  '{"id":1,"admin_graphql_api_id":"gid://shopify/Order/1"}',
);

Deno.test("webhook HMAC: correct header passes", async () => {
  assert.equal(
    await verifyWebhookHmac(body, b64(await hmac(SECRET, body)), SECRET),
    true,
  );
});

Deno.test("webhook HMAC: one changed byte, wrong secret, missing or junk header fail", async () => {
  const header = b64(await hmac(SECRET, body));
  const changed = body.slice();
  changed[5] ^= 1;
  assert.equal(await verifyWebhookHmac(changed, header, SECRET), false);
  assert.equal(
    await verifyWebhookHmac(body, b64(await hmac("other", body)), SECRET),
    false,
  );
  assert.equal(await verifyWebhookHmac(body, null, SECRET), false);
  assert.equal(await verifyWebhookHmac(body, "not base64!", SECRET), false);
  assert.equal(
    await verifyWebhookHmac(body, b64(new Uint8Array(16)), SECRET),
    false,
  );
  assert.equal(await verifyWebhookHmac(body, header, ""), false);
});

// ---------- Session token (JWT) ----------

Deno.test("session token: valid -> shop from dest", async () => {
  assert.deepEqual(await verifySessionToken(await jwt(goodClaims()), check), {
    shop: "shop-a.myshopify.com",
  });
});

Deno.test("session token: aud as an array containing the key is accepted", async () => {
  const t = await jwt({ ...goodClaims(), aud: ["other", API_KEY] });
  assert.deepEqual(await verifySessionToken(t, check), {
    shop: "shop-a.myshopify.com",
  });
});

Deno.test("session token: within the 10 s leeway is accepted", async () => {
  const t = await jwt({
    ...goodClaims(),
    exp: NOW / 1000 - 9,
    nbf: NOW / 1000 + 9,
  });
  assert.notEqual(await verifySessionToken(t, check), null);
});

Deno.test("session token: every bad case is refused", async () => {
  const c = goodClaims();
  const bad: [string, Promise<string>][] = [
    ["wrong aud", jwt({ ...c, aud: "someone-else" })],
    ["expired", jwt({ ...c, exp: NOW / 1000 - 11 })],
    ["not yet valid", jwt({ ...c, nbf: NOW / 1000 + 11 })],
    ["missing exp", jwt({ ...c, exp: undefined })],
    ["missing nbf", jwt({ ...c, nbf: undefined })],
    ["missing aud", jwt({ ...c, aud: undefined })],
    ["missing dest", jwt({ ...c, dest: undefined })],
    ["dest not myshopify", jwt({ ...c, dest: "https://evil.com" })],
    ["dest http", jwt({ ...c, dest: "http://shop-a.myshopify.com" })],
    [
      "dest with port",
      jwt({ ...c, dest: "https://shop-a.myshopify.com:8443" }),
    ],
    [
      "iss host differs",
      jwt({ ...c, iss: "https://shop-b.myshopify.com/admin" }),
    ],
    ["exp as text", jwt({ ...c, exp: String(NOW / 1000 + 60) })],
    ["alg none", jwt(c, { alg: "none", typ: "JWT" })],
    ["alg RS256", jwt(c, { alg: "RS256", typ: "JWT" })],
    ["wrong secret", jwt(c, undefined, "other-secret")],
  ];
  for (const [name, token] of bad) {
    assert.equal(await verifySessionToken(await token, check), null, name);
  }
  const good = await jwt(c);
  const [h, p] = good.split(".");
  assert.equal(await verifySessionToken(`${h}.${p}`, check), null, "2 parts");
  assert.equal(
    await verifySessionToken(`${h}.${p}.`, check),
    null,
    "empty signature",
  );
  const tampered = `${h}.${
    jsonPart({ ...c, dest: "https://shop-b.myshopify.com" })
  }.${good.split(".")[2]}`;
  assert.equal(
    await verifySessionToken(tampered, check),
    null,
    "tampered claims",
  );
  assert.equal(
    await verifySessionToken("x".repeat(5000), check),
    null,
    "too long",
  );
  assert.equal(
    await verifySessionToken(good, { ...check, secret: "" }),
    null,
    "no secret configured",
  );
});

// ---------- constant-time compare ----------

Deno.test("constantTimeEqual: equal, different, different length", async () => {
  assert.equal(await constantTimeEqual("cron-secret", "cron-secret"), true);
  assert.equal(await constantTimeEqual("cron-secret", "cron-secreT"), false);
  assert.equal(await constantTimeEqual("cron-secret", "cron"), false);
  assert.equal(await constantTimeEqual("", "x"), false);
});

// ---------- shop domain (spec 05 rules) ----------

Deno.test("shop domain: spec 05 examples", () => {
  for (
    const input of [
      "MyShop",
      "https://myshop.myshopify.com/admin/orders",
      "myshop.myshopify.com",
    ]
  ) {
    assert.equal(normalizeShopDomain(input), "myshop.myshopify.com", input);
  }
  assert.equal(isValidShopDomain(normalizeShopDomain("myshop.com")), false);
  assert.equal(isValidShopDomain("-shop.myshopify.com"), false);
  assert.equal(isValidShopDomain("myshop.myshopify.com"), true);
  assert.equal(isValidShopDomain("myshop.myshopify.com.evil.com"), false);
});
