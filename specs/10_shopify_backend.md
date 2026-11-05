# 10 Shopify (backend)

Purpose
Connect a merchant's Shopify store to BDPay, turn each new BDPay order into a payment session
with a pay link, and mark the Shopify order paid when the payment is verified. The customer-facing
button on Shopify's Thank-you and Order status pages comes in spec 10a.

Scope
- Edge Functions (TypeScript, Deno) in supabase/functions/:
  shopify-connect-link, shopify-oauth-callback, shopify-webhooks, shopify-paylink, shopify-sync, shopify-status.
- Shared code in supabase/functions/_shared/:
  shopify_client.ts (ShopifyClient interface + real fetch implementation), fake_shopify.ts (for tests),
  shopify_auth.ts (OAuth query HMAC, webhook HMAC, extension session token check),
  shopify_orders.ts (order -> session rules), shopify_notifier.ts (OrderNotifier for Shopify),
  money_text.ts (Shopify amount text -> poisha), and Store additions listed in Contract.
- Change to spec 09: the pay token is no longer random. token = base64url(HMAC-SHA256(env PAY_TOKEN_SECRET,
  sessionId)). The store still keeps only SHA-256(token). This lets BDPay rebuild the pay link at any time.
  Spec 09 tests that check token handling are updated for this; no other spec 09 change.
- Deno tests in supabase/functions/tests/ using FakeStore and FakeShopify. No real Shopify calls in tests.
- Environment variables (names only; values are never in code): SHOPIFY_API_KEY, SHOPIFY_API_SECRET,
  SHOPIFY_SCOPES (read_orders,write_orders), SHOPIFY_API_VERSION (for example 2026-10), FUNCTIONS_URL,
  PAY_PAGE_URL, PAY_TOKEN_SECRET, CRON_SECRET.
- Not in scope: the Shopify app config file and the checkout extension (spec 10a), SQL and the real
  token vault (spec 12), app screen changes (spec 13), alerts (spec 11).

Contract
Store additions (spec 12 builds tables from these):
  createInstallState(merchantId, shopDomain) -> state (random, valid 10 minutes, single use)
  consumeInstallState(state) -> {merchantId, shopDomain} | null
  upsertShopifyStore({merchantId, shopDomain}) -> Store   (one active store per merchant; a shop belongs
      to one merchant only)
  saveShopifyTokens(storeId, {accessToken, accessExpiresAt, refreshToken, refreshExpiresAt})
      (spec 12 keeps these in Supabase Vault, never in plain columns)
  getShopifyTokens(storeId) -> tokens | null
  getStoreByShopDomain(shopDomain) -> Store | null
  getStoreForMerchant(merchantId) -> Store | null
  setStoreStatus(storeId, active | uninstalled, lastError (or null))
  markWebhookSeen(webhookId) -> boolean (true the first time)
  findSessionByExternalOrder(storeId, externalOrderId) -> PaymentSession | null
  createPaymentSession must be idempotent on (storeId, externalOrderId): a second call returns the first session.
  expireSessionForOrder(storeId, externalOrderId) -> void (only when status is open or pending)
  enqueueOrderSync(sessionId) -> OrderSync (one per session)
  listDueOrderSyncs(now, limit) -> OrderSync[]
  updateOrderSync(id, {status, attempts, nextAttemptAt, lastError})
OrderSync: id, merchantId, sessionId, status (pending | done | failed), attempts, nextAttemptAt, lastError.

ShopifyClient:
  exchangeCode(shop, code) -> tokens        (POST https://{shop}/admin/oauth/access_token with expiring=1)
  refresh(shop, refreshToken) -> tokens     (same endpoint, grant_type=refresh_token; returns a NEW pair)
  graphql(shop, accessToken, query, variables) -> {data, errors}
Token rule: before any Admin call, if accessExpiresAt is less than 5 minutes away, refresh first and save
the new pair. If the refresh fails with an invalid grant, set the store lastError "reconnectNeeded".

Order -> session rules (shopify_orders.ts, pure):
Read the order with GraphQL fields: id, name, displayFinancialStatus, paymentGatewayNames, cancelledAt,
statusPageUrl, totalOutstandingSet { shopMoney { amount currencyCode } }.
A session is created only when ALL are true:
  1. one of paymentGatewayNames contains "bdpay" (case-insensitive);
  2. cancelledAt is null; 3. displayFinancialStatus is PENDING;
  4. currencyCode is BDT; 5. outstanding amount > 0.
Otherwise the result is a reason: notBdpay | cancelled | alreadyPaid | wrongCurrency | zeroAmount.
Session fields: orderRef = order name (for example "#1045"), externalOrderId = order id (gid),
amountPoisha = outstanding amount (money_text: "1250.00" -> 125000, "1250.5" -> 125050, "1250" -> 125000;
whole-number math only, no float), returnUrl = statusPageUrl.
Pay link = PAY_PAGE_URL + "?t=" + token.

Function contracts (JSON unless said; errors are {ok: false, error, message}):

1. shopify-connect-link (Supabase user token; user owns a merchant)
   POST {shopDomain} -> 200 {ok: true, url}
   - Normalize and check the domain with the spec 05 rules -> 400 invalidDomain.
   - The shop already belongs to ANOTHER merchant -> 409 shopTaken.
   - url = https://{shop}/admin/oauth/authorize?client_id=...&scope=SHOPIFY_SCOPES
     &redirect_uri=FUNCTIONS_URL/shopify-oauth-callback&state=STATE (offline access, no per-user grant).

2. shopify-oauth-callback (GET from Shopify; returns a small Bangla HTML page, not JSON)
   - Check the query HMAC with SHOPIFY_API_SECRET (constant-time) -> page "লিংকটি সঠিক নয়".
   - shop must match ^[a-z0-9][a-z0-9-]*\.myshopify\.com$ and the state's shop -> same error page.
   - consumeInstallState; missing or used -> page "লিংকের মেয়াদ শেষ — অ্যাপ থেকে আবার চেষ্টা করুন".
   - exchangeCode, upsertShopifyStore, saveShopifyTokens, setStoreStatus active. Audit "shopify.connect".
   - Success page: "✓ Shopify যুক্ত হয়েছে — BDPay অ্যাপে ফিরে যান". The page uses the pay page colors,
     has no scripts and shows no tokens.

3. shopify-webhooks (POST from Shopify)
   - Check X-Shopify-Hmac-Sha256 = base64(HMAC-SHA256(raw body, SHOPIFY_API_SECRET)), constant-time
     -> 401. Read X-Shopify-Topic, X-Shopify-Shop-Domain, X-Shopify-Webhook-Id.
   - markWebhookSeen false -> 200 (already handled).
   - Answer within 5 seconds; heavy work is skipped rather than slowing the reply.
   - Topics:
     orders/create: find the store by shop; read the order by its admin_graphql_api_id with GraphQL;
       apply the order rules; create the session if allowed. Not allowed -> 200, nothing created.
     orders/cancelled: expireSessionForOrder.
     app/uninstalled: setStoreStatus uninstalled, remove its tokens. Audit "shopify.uninstall".
     customers/data_request, customers/redact, shop/redact: 200, write an audit entry with the topic.
       shop/redact also removes the store's tokens. (BDPay reads no Shopify customer details.)
     Any other topic -> 200 and ignored.

4. shopify-paylink (called by the spec 10a extension)
   Authorization: Bearer <Shopify session token>. The token is a JWT signed HS256 with SHOPIFY_API_SECRET;
   check signature, aud = SHOPIFY_API_KEY, exp and nbf (10 s leeway), and take the shop from the dest claim
   -> 401 badSessionToken.
   POST {orderId} (the order gid) ->
   200 {ok: true, status: ready, payUrl, sessionStatus} | {status: notBdpay} | {status: alreadyPaid}
       | {status: notReady}
   - Find the session; if missing, read the order now and create it with the same rules
     (a race with orders/create is safe because creation is idempotent).
   - Order not found yet (Shopify still creating it) -> notReady (the extension retries).
   - Session verified -> ready with sessionStatus verified (the button changes, spec 10a).
   - CORS: allow any origin for this function only (it is protected by the session token).
   - Rate limit 30 per minute per shop.

5. ShopifyNotifier.onSessionVerified(session) (plugged into spec 09)
   - enqueueOrderSync, then try once right away.
   - Try = orderMarkAsPaid(input: {id: externalOrderId}), then tagsAdd(id, ["BDPay-verified"]).
   - Success -> done. Order already paid or cancelled (Shopify userErrors) -> done with lastError
     "alreadyPaid" or "cancelled", no retry. Network or 5xx or 429 -> pending, retry later.
   - Retry wait: 1, 2, 5, 10, 30, then every 60 minutes; after 24 attempts -> failed (spec 11 alerts).

6. shopify-sync (header X-Cron-Secret = CRON_SECRET, else 401; called every 5 minutes)
   POST {} -> processes up to 50 due OrderSyncs -> 200 {ok: true, done, retried, failed}.

7. shopify-status (Supabase user token)
   GET -> 200 {ok: true, connected, shopDomain (or null), lastError (or null)}.
   connected = store exists, status active, tokens exist, lastError not reconnectNeeded.

Functional rules
- BDPay never asks the merchant for a Shopify password or API token. Connecting is only through OAuth.
- Tokens are never returned by any function, logged or put in HTML.
- A Shopify mark-paid failure never changes the BDPay payment result. Verified stays verified.
- Webhooks are idempotent: the same webhook delivered twice changes nothing the second time.
- All money is integer poisha.

Edge cases
- Customer pays and the order is cancelled before verification -> session expired, nothing marked paid.
- orders/create arrives after the extension already created the session -> no second session.
- The merchant reconnects the same shop -> same store row, new tokens.
- The same shop tries to connect to a second merchant -> shopTaken.
- A store in USD -> wrongCurrency, no session, the extension shows nothing (spec 10a).
- An order paid by card (no "bdpay" gateway) -> notBdpay.
- Refresh token expired after 90 days unused -> lastError reconnectNeeded; shopify-status shows
  connected false; syncs wait (pending) and do not count attempts until reconnected.
- Webhook with a wrong HMAC -> 401, nothing done.
- The session token for shop A used to ask for an order of shop B -> notBdpay (the order is looked up
  only inside shop A's store).

Non-functional rules
- Never log tokens, codes, secrets, customer data, TrxIDs or full webhook bodies.
- Handlers use only the Store and ShopifyClient interfaces.
- deno check, deno lint and deno fmt --check pass.

Acceptance criteria
- deno test supabase/functions/tests passes (specs 08 and 09 still pass), covering:
  - money_text examples; order rules: allowed + each reason.
  - OAuth: query HMAC ok / bad; state used twice; shop mismatch; success saves tokens (no token in the page).
  - token refresh: under 5 minutes -> refresh and new pair saved; invalid grant -> reconnectNeeded.
  - webhooks: bad HMAC 401; orders/create creates one session; the same webhook id twice -> one session;
    orders/cancelled expires an open session but not a verified one; app/uninstalled removes tokens;
    the three privacy topics return 200 with audit.
  - paylink: bad token, wrong aud, expired; ready with a working pay URL (its token opens the session
    through pay-session from spec 09); notReady; notBdpay; alreadyPaid; extension-first then webhook -> one session.
  - notifier: success -> done and tag added; alreadyPaid userError -> done, no retry; 503 -> pending with
    the next wait; 24 failures -> failed; a mark-paid failure leaves the session verified.
  - shopify-sync: wrong secret 401; processes due items only.
  - pay token: the same sessionId always gives the same token; a changed token finds nothing.
- deno check, deno lint and deno fmt --check pass.
- Local smoke test with BDPAY_FAKE_STORE=1 and FakeShopify (supabase/scripts/smoke_shopify.ts):
  a signed orders/create webhook -> session -> pay URL printed -> device SMS + TrxID -> verified ->
  FakeShopify shows orderMarkAsPaid called once.

Assumptions
- Specs 01 to 09 are done.
- A Shopify Partner account and a development store exist for the live test in spec 10a.
- BDPay reads only order fields listed above. Shopify may still require a protected customer data
  request for order webhooks; this is checked in spec 10a.
- SHOPIFY_API_VERSION is set to the latest stable version at build time.
