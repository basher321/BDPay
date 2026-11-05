# Plan 10 - Shopify (backend)

Spec: specs/10_shopify_backend.md (builds on 05 for the shop-domain rules, 09 for sessions, the notifier and tokens)

## 0. Blocker carried over

- Spec 08 does not exist, and of spec 09 only supabase/functions/_shared/match_rules.ts (+ its test) is built.
- Spec 10 adds methods to spec 08/09's Store and FakeStore, changes spec 09's token.ts, plugs a notifier into spec 09,
  needs spec 09's pay-session for its "working pay URL" test, and spec 08's device SMS for its smoke test.
- So: the pure parts (money_text, shopify_auth, shopify_orders, the ShopifyClient + FakeShopify, the token-refresh
  rule) can be built now. Everything touching the Store, sessions or other functions waits for specs 08 and 09.
- Every "[CHANGED 09]" / "[CHANGED 08]" item below is inferred from the specs, not read from code.

Decisions needed before execution
- D37. **Build order given the blocker.** Options: A (recommended) build the pure parts now (sections 2 steps 1-3),
  the rest after specs 08 and 09; B wait for everything.
- D38. **A webhook marked "seen" before its work finishes is lost if the work fails.** markWebhookSeen happens first
  (spec), so if the GraphQL read then fails, Shopify's retry is ignored and no session is created. Proposal: mark it
  seen only after the work succeeded (the work is idempotent anyway: createPaymentSession, expireSessionForOrder and
  token removal can safely run twice); on failure answer 500 so Shopify retries. The extension's paylink also
  creates missing sessions, so a lost orders/create is not fatal either way.
- D39. **Two refreshes at once break the store.** Shopify returns a new refresh token and the old one stops working.
  If two requests refresh at the same moment, the second gets "invalid grant" and the store would wrongly be marked
  reconnectNeeded. Proposal: a store-level compare-and-swap - `swapShopifyTokens(storeId, oldRefreshToken, newPair)`
  -> "ok" | "changed"; on invalid grant, re-read the tokens first and only mark reconnectNeeded if they did not change.
- D40. **Store methods the spec uses but does not list:** removeShopifyTokens(storeId) (app/uninstalled, shop/redact),
  getMerchantIdForUser(userId) (connect-link, status - same as plan 09 D28), appendAudit (if spec 08 has none),
  swapShopifyTokens (D39).
- D41. **The OAuth callback returns an HTML page - check this works on hosted Supabase.** Supabase Edge Functions have
  been documented as not serving text/html to browsers (responses shown as plain text) unless a custom domain is used.
  If that is still true, the Bangla success/error pages will show as raw text. Options: A redirect to static pages on
  the pay page's host (pay_page/shopify-ok.html etc.) - OUTSIDE spec 10's scope (it changes pay_page), so it needs a
  spec change first; B (the plan's default) keep the HTML response exactly as the spec says and confirm it on the
  live test (spec 10a), with a custom domain if needed. Decide after checking the current Supabase docs.
- D42. **paylink: an order of another shop looks the same as "not created yet".** The session token's shop is used
  to read the order; an order id from shop B simply comes back as not found in shop A, so the function cannot tell
  "notBdpay" (spec edge case) from "notReady". Options: B answer notReady and let the extension give up after its
  retries (spec 10a); C answer notBdpay whenever the order is not found (breaks the "Shopify still creating it" case).
  Recommended: B, and change the edge case text. Either way, nothing of shop B is ever read.
- D43. **paylink status for cancelled / wrongCurrency / zeroAmount orders.** The response list has only ready,
  notBdpay, alreadyPaid, notReady. Proposal: cancelled, wrongCurrency and zeroAmount answer notBdpay (the extension
  shows nothing); also always include ok: true in these answers (the spec's examples drop it).
- D45. **Optional extra check: OAuth timestamp freshness.** Shopify sends a timestamp in the callback query; the spec
  does not ask to check it. The single-use, 10-minute state already blocks replays, so this is belt-and-braces and
  NOT built unless you say yes.
- D44. **Privacy webhooks vs "never delete".** customers/redact may legally require removing a customer's data, but
  BDPay keeps the payer's phone number in SMS records (spec 08) and sessions keep the order status-page URL, and
  CLAUDE.md says SMS records are never deleted. The spec only writes an audit entry. Needs a product/legal decision
  (e.g. blank the payer number while keeping the record); this plan does what the spec says.

## 1. Files

### New - supabase/functions/_shared/
- money_text.ts - "1250.00" -> 125000, "1250.5" -> 125050, "1250" -> 125000; integer math on the string, no float;
  refuses negatives, more than 2 decimals, exponents and junk.
- shopify_auth.ts - all checks fail closed (any missing or odd value = reject):
  - verifyOAuthQueryHmac: drop "hmac" (and "signature"), sort the rest by key, join key=value with "&", HMAC-SHA256
    hex with SHOPIFY_API_SECRET; the received hmac must be 64 lower-case hex chars; compare with
    crypto.subtle.verify (constant-time by design) on the decoded bytes. Duplicate keys -> reject.
  - verifyWebhookHmac: HMAC-SHA256 over the RAW body bytes (read once, before any JSON parse); the header is
    base64-decoded and checked with crypto.subtle.verify. Missing header -> reject.
  - verifySessionToken (JWT): exactly 3 parts, size limit; header alg must be "HS256" (so "none" and RS* are
    refused) and typ JWT if present; signature checked with crypto.subtle.verify (constant-time); claims all
    required: aud equals SHOPIFY_API_KEY (string, or an array containing it), exp > now - 10 s, nbf <= now + 10 s,
    dest is https://<shop> with a valid myshopify.com shop; if iss is present its host must equal dest's host.
    The shop is taken only from dest. Missing exp, nbf, aud or dest -> reject.
  - constantTimeEqual(a, b) for plain strings (CRON_SECRET): both sides hashed with SHA-256 first, then compared byte
    by byte without early exit, so neither the content nor the length leaks.
  - normalizeShopDomain / isValidShopDomain: spec 05 rules, ported from app/lib/core/validators.dart.
- shopify_orders.ts - pure order rules: evaluateOrder(order) -> {allowed, fields} | {reason}; the ORDER_QUERY text.
- shopify_client.ts - ShopifyClient interface; FetchShopifyClient (exchangeCode, refresh, graphql with
  X-Shopify-Access-Token header and SHOPIFY_API_VERSION); typed errors (invalidGrant, rateLimited, server, network)
  that carry a status code only, never a body; withFreshToken(store, client, storeRecord) - the 5-minute refresh rule.
- fake_shopify.ts - FakeShopify: orders by shop, token pairs, call log, scripted failures (503, 429, invalid grant,
  userErrors), for tests and the smoke script.
- shopify_notifier.ts - ShopifyNotifier (OrderNotifier): enqueue + one immediate try; tryOrderSync() shared with
  shopify-sync; the retry schedule as a pure function nextWait(attempts).
- pay_link.ts - payLink(token) = PAY_PAGE_URL + "?t=" + token (one place; used by paylink and the smoke script).

### New - functions (each handler.ts with injected deps + index.ts wiring Deno.serve and env)
- shopify-connect-link - POST {shopDomain}; invalidDomain / shopTaken / authorize URL with a new install state.
- shopify-oauth-callback - GET; HMAC, shop, state checks; code exchange; store + tokens; audit; small Bangla pages
  built from fixed text only - no query value (shop, state, code, hmac) is ever echoed into the page; no scripts
  (Content-Security-Policy: default-src 'none'; style via a fixed hash; frame-ancestors 'none'); Cache-Control: no-store.
- shopify-webhooks - POST; HMAC on raw bytes; topics per spec; dedupe per D38.
- shopify-paylink - POST {orderId}; session token; find or create the session; any-origin CORS; 30/min per shop.
- shopify-sync - POST; X-Cron-Secret; up to 50 due syncs.
- shopify-status - GET; connected / shopDomain / lastError.

### New tests (supabase/functions/tests/)
money_text_test, shopify_auth_test, shopify_orders_test, shopify_client_test (refresh rule, D39 race, error
redaction), shopify_connect_link_test, shopify_oauth_callback_test, shopify_webhooks_test, shopify_paylink_test,
shopify_notifier_test, shopify_sync_test, shopify_status_test, pay_token_test, shopify_helpers.ts (signed webhook /
query / JWT builders with a test secret).

### New script
supabase/scripts/smoke_shopify.ts - in-process FakeStore + FakeShopify run (needs spec 08 device SMS and spec 09).

### [CHANGED 09] (not built yet - see section 0)
- _shared/token.ts - pay token = base64url(HMAC-SHA256(PAY_TOKEN_SECRET, sessionId)); hash = SHA-256(token) as before.
- spec 09's token tests - updated for the deterministic token (only those).
- The notifier wiring in pay-session, claim-review and the Matcher: ShopifyNotifier instead of NoopNotifier.
- createPaymentSession: idempotent on (storeId, externalOrderId) and sets the token hash from the session id.

### [CHANGED 08/09] Store (not built yet)
- store.ts / fake_store.ts: every Store addition in the spec's Contract + D39/D40; OrderSync and install-state maps;
  webhook-seen set; the idempotent createPaymentSession (one block, so two creators at once get the same session).

## 2. Order of work

1. money_text.ts + test; shopify_auth.ts + test (HMACs, JWT, domain rules). `deno test`, check, lint, fmt.
2. shopify_orders.ts + test (allowed + each reason).
3. shopify_client.ts (interface, fetch client, withFreshToken), fake_shopify.ts + shopify_client_test.
   -- Steps 1-3 need nothing from specs 08/09 (D37 = A). --
4. Store additions in FakeStore (+ D39/D40); spec 09 token.ts change + its tests; pay_link.ts + pay_token_test.
5. Functions, each with its test: connect-link -> oauth-callback -> webhooks -> paylink -> notifier (+ spec 09
   wiring) -> sync -> status.
6. smoke_shopify.ts.
7. Full deno test (specs 08, 09 still green), deno check, deno lint, deno fmt --check; the searches in section 3.

## 3. Acceptance criteria -> check

| Criterion | Check |
|---|---|
| deno test passes, specs 08 and 09 too | full `deno test supabase/functions/tests` (needs specs 08/09) |
| money_text examples | money_text_test ("1250.00", "1250.5", "1250", "0.5"; "-1", "1e3", "12.345", "" and "abc" refused) |
| order rules: allowed + each reason | shopify_orders_test (notBdpay, cancelled, alreadyPaid, wrongCurrency, zeroAmount; "BDPay" case-insensitive) |
| OAuth: query HMAC ok / bad | shopify_auth_test + shopify_oauth_callback_test |
| OAuth: state used twice | oauth_callback_test (second time -> expired page) |
| OAuth: shop mismatch | oauth_callback_test (bad pattern; shop != state's shop) |
| OAuth: success saves tokens, no token in the page | oauth_callback_test (FakeStore has the pair; page text contains none of the fixture tokens or the code) |
| token refresh under 5 minutes -> refresh, new pair saved | shopify_client_test |
| invalid grant -> reconnectNeeded | shopify_client_test (+ D39: a parallel refresh is not reconnectNeeded) |
| webhooks: bad HMAC 401 | shopify_webhooks_test |
| orders/create creates one session; same webhook id twice -> one session | shopify_webhooks_test |
| orders/cancelled expires open, not verified | shopify_webhooks_test |
| app/uninstalled removes tokens | shopify_webhooks_test (+ audit) |
| 3 privacy topics -> 200 with audit (shop/redact removes tokens) | shopify_webhooks_test |
| paylink: bad token, wrong aud, expired | shopify_paylink_test (+ nbf in the future, wrong alg, bad signature) |
| paylink: ready with a working pay URL (opens the session via pay-session) | shopify_paylink_test calls spec 09's pay-session handler with the token from payUrl (needs spec 09) |
| paylink: notReady, notBdpay, alreadyPaid | shopify_paylink_test |
| extension first, then webhook -> one session | shopify_paylink_test (+ both at once) |
| notifier: success -> done + tag | shopify_notifier_test (orderMarkAsPaid then tagsAdd, BDPay-verified) |
| notifier: alreadyPaid userError -> done, no retry | shopify_notifier_test |
| notifier: 503 -> pending with the next wait | shopify_notifier_test (1, 2, 5, 10, 30, 60 ... minutes) |
| notifier: 24 failures -> failed | shopify_notifier_test |
| mark-paid failure leaves the session verified | shopify_notifier_test (+ spec 09 flow) |
| shopify-sync: wrong secret 401; only due items | shopify_sync_test (not-yet-due and reconnectNeeded stores skipped, attempts unchanged) |
| pay token: same id -> same token; a changed token finds nothing | pay_token_test |
| deno check / lint / fmt --check | the three commands |
| smoke test: webhook -> session -> pay URL -> SMS + TrxID -> verified -> orderMarkAsPaid once | you run smoke_shopify.ts (needs specs 08/09) |

Other rules checked too

| Rule | Check |
|---|---|
| shopify-status connected rule | shopify_status_test (no store, uninstalled, no tokens, reconnectNeeded, all ok) |
| connect-link: invalidDomain, shopTaken, URL parts | shopify_connect_link_test (client_id, scope, redirect_uri, state; no grant_options[]) |
| Reconnect same shop -> same store row, new tokens | oauth_callback_test |
| Order cancelled before verification -> session expired, nothing marked paid | shopify_webhooks_test (cancel, then the SMS + TrxID flow finds an expired session; FakeShopify has no orderMarkAsPaid call) |
| Audit "shopify.connect" and "shopify.uninstall" written | oauth_callback_test, shopify_webhooks_test |
| BDPay never asks for a Shopify password or API token | review + search: no handler reads a password / token field from a request body; connecting is only connect-link + OAuth |
| HMAC/JWT edge cases fail closed | shopify_auth_test: alg none, alg RS256, missing exp / nbf / aud / dest, aud array, iss host != dest host, dest not myshopify, 2-part token, wrong-length hmac, upper-case hex, duplicate query keys, missing webhook header, body changed by one byte |
| Fixed error codes only in lastError / responses | shopify_client_test + shopify_status_test: a FakeShopify error message never appears in the store or a response |
| reconnectNeeded: syncs wait, attempts not counted | shopify_sync_test |
| Session token of shop A, order of shop B -> nothing of B is read | shopify_paylink_test (FakeShopify: lookup only in shop A; D42) |
| Rate limit 30/min per shop on paylink | shopify_paylink_test (31st -> 429) |
| Webhook answers within 5 s | shopify_webhooks_test with a slow FakeShopify: the handler returns in time (time budget) |
| Handlers use only Store and ShopifyClient | review + search: no fetch( outside shopify_client.ts |
| Money integer poisha | money_text_test; search: no parseFloat / Number( on amounts |
| Never log tokens, codes, secrets, customer data, TrxIDs, bodies | recording logger in every test: none of the fixture secret, tokens, code, state, body text appears (section 4) |
| No tokens in any response or HTML | every handler test scans the response body for the fixture tokens |
| No remote imports (nothing downloaded) | search: no https:, npm: or jsr: imports |
| UTF-8 without BOM | search |

## 4. Every place a token or secret is handled

| Item | Where it is used | Stays out of logs and responses because |
|---|---|---|
| SHOPIFY_API_SECRET | OAuth query HMAC, webhook HMAC, session-token JWT signature | read from env into the verifier only; compared with constantTimeEqual; never passed to the logger; error messages are fixed text |
| SHOPIFY_API_KEY | client_id in the authorize URL; aud check | public by design (it is in the URL Shopify shows); still not logged |
| OAuth code | callback query -> exchangeCode | used once, never stored or logged; note: it is in the callback URL, so platform access logs may record it (Shopify's design; single use, short-lived) |
| Install state | connect-link creates, callback consumes | random 32 bytes, single use, 10 minutes; the store may keep only its hash (planned); never logged |
| Access token | Admin GraphQL calls | sent only in the X-Shopify-Access-Token header (never in a URL); kept in memory per request; never in responses, HTML, audit or logs |
| Refresh token | refresh call body | same; D39 swap compares tokens inside the store, not in logs |
| Token pair storage | saveShopifyTokens / getShopifyTokens / remove | FakeStore now; Supabase Vault in spec 12, never plain columns |
| Shopify error bodies | fetch client | errors carry a status code only; bodies (which can echo input) are dropped |
| Webhook body | HMAC check, topic handlers | read as raw bytes for the HMAC; only the needed ids are taken; never logged |
| Session token (JWT) | paylink Authorization header | verified, its shop used; never logged or returned |
| PAY_TOKEN_SECRET | pay token = HMAC(secret, sessionId) | env only; the pay token goes to the customer in payUrl by design and is never logged; the store keeps SHA-256(token) |
| CRON_SECRET | shopify-sync header | constant-time compare; never logged |
| Test values | fixtures | fake secrets made up in the tests; no .env file is read (CLAUDE.md) |
| Install state at rest | install-state store | only SHA-256(state) is stored; the raw state lives in the authorize URL only |
| GraphQL `errors` and `userErrors` | client / notifier | mapped to fixed codes (alreadyPaid, cancelled, rateLimited, server, network, reconnectNeeded); Shopify's message text is never stored, logged or returned |
| lastError (store, OrderSync) and shopify-status | store, status response | only the fixed codes above; never raw error text |
| Webhook payload / customer data | orders/create (email, address, phone are in it) | only admin_graphql_api_id and the topic headers are read; the parsed body is never logged, stored or audited |
| Privacy-topic audit entries | customers/data_request, customers/redact, shop/redact | audit holds topic, shop domain and webhook id only - no customer ids, emails, phones or orders from the payload |
| JWT claims | paylink | sub (may be a customer id) and the raw token are never logged; only the shop from dest is used |
| Callback pages | oauth-callback | fixed text only; no query values echoed; no-store |
| Exceptions | everywhere | the logger takes the error name and request id only; exception messages (which can include URLs or input) are never logged or returned |

The recording logger (one test helper) fails any test whose log lines contain a fixture secret, token, code, state,
webhook body, TrxID or customer field.

## 5. Unclear or wrong in the spec, and Shopify API points to check

Spec
1. Blocker: specs 08/09 -> D37. Webhook dedupe order -> D38. Refresh race -> D39. Missing store methods -> D40.
2. HTML from Edge Functions -> D41. Other-shop orders -> D42. paylink statuses -> D43. Privacy webhooks -> D44.
3. **Deterministic pay token.** Rotating PAY_TOKEN_SECRET changes every token, so all open pay links stop working and
   stored hashes no longer match. Noted: rotation needs a plan (keep the old secret for lookups during a grace time).
4. **Two env names for the pay page:** PAY_PAGE_URL (spec 10) and PAY_PAGE_ORIGIN (spec 09 CORS). Both are needed;
   PAY_PAGE_ORIGIN must be the origin of PAY_PAGE_URL. A test checks they agree.
5. **OAuth callback freshness.** Shopify also sends a timestamp; the spec does not ask for a check -> D45 (not built
   by default).
6. **returnUrl = statusPageUrl** is a link that opens the customer's order page. It is returned to the pay page (spec
   07) by design; it is not logged.
7. **The retry count.** "1, 2, 5, 10, 30, then every 60 minutes; after 24 attempts -> failed": plan counts the immediate
   try as attempt 1, so waits are before attempts 2..24 (about 20 hours in total).
8. **CLAUDE.md:** every merchant-owned record has merchantId (install state, store, tokens, OrderSync: yes; the
   webhook-seen set is global by webhook id, not merchant data). Shopify tokens are never read from .env (CLAUDE.md
   forbids reading them); they live only in the store. Nothing is downloaded: the JWT check uses Web Crypto.
   Times (accessExpiresAt, refreshExpiresAt, nextAttemptAt, install-state expiry) are stored as ISO 8601 UTC.
   "Never delete": expireSessionForOrder only changes status; tokens are removed (they are secrets, not payment
   records); sessions, claims and matches stay.

Shopify's current API - check against the docs at build time (I can't verify these offline)
9. **Expiring offline tokens.** Check that `expiring=1` on /admin/oauth/access_token still returns expires_in,
   refresh_token and refresh_token_expires_in, the refresh grant name (grant_type=refresh_token), and the lifetimes
   (the spec assumes a 90-day refresh token).
10. **Authorization-code OAuth vs token exchange.** Shopify pushes embedded apps toward Shopify-managed install +
    token exchange. Check that the authorization-code flow is still allowed for this app type (an app whose UI is a
    checkout extension plus the BDPay app outside Shopify).
11. **Order fields.** Check that `paymentGatewayNames`, `displayFinancialStatus` (value PENDING), `totalOutstandingSet`,
    `statusPageUrl` and `cancelledAt` still exist in the chosen API version (paymentGatewayNames has been a candidate for
    deprecation).
12. **Mutations.** Check `orderMarkAsPaid(input: {id})` (needs write_orders; only works with an outstanding balance) and
    the exact userErrors it returns for "already paid" and "cancelled" - the plan matches on error codes, not on
    message text, so the codes must be confirmed. Check `tagsAdd(id, tags)`.
13. **Webhook headers.** X-Shopify-Hmac-Sha256, X-Shopify-Topic, X-Shopify-Shop-Domain, X-Shopify-Webhook-Id; check
    whether Shopify now recommends X-Shopify-Event-Id for de-duplication.
14. **Session tokens from checkout / Thank-you extensions.** Check the claims (aud, dest, iss, sub) and that dest is the
    shop URL; check the 1-minute lifetime and leeway.
15. **Order id on the Thank-you page.** The Thank-you page gives an OrderConfirmation whose id may be an OrderIdentity
    gid, not the Order gid, and the order may not exist yet. Check what the extension can send (spec 10a) and whether
    the Admin API can look it up.
16. **Protected customer data.** orders/create webhooks and reading orders may need approved protected-customer-data
    access even though BDPay reads no customer fields (the spec's own assumption) - check in the Partner dashboard.
17. **Compliance webhooks** (customers/data_request, customers/redact, shop/redact) are set in the app config (spec 10a);
    check their payload shape for the audit entry.
18. **API version.** Versions are quarterly (yyyy-01/04/07/10); pick the latest stable one at build time.

## 6. Review log

Review 1 against spec 10 and CLAUDE.md:
- Scope: no extension, app config, SQL or Flutter work. D41 option A (pages on pay_page) is now marked as outside
  scope and needing a spec change; the plan's default is the spec's HTML page. The OAuth timestamp check was a plan
  default beyond the spec -> now optional D45.
- Leaks: added install state stored as a hash; GraphQL errors / userErrors and lastError limited to fixed codes;
  webhook payloads (customer data) never logged, stored or audited - privacy audit entries hold topic, shop and
  webhook id only; callback pages never echo query values and are no-store; JWT sub never logged; exception
  messages never logged or returned.
- HMAC/JWT: all checks now use crypto.subtle.verify (constant-time) on decoded bytes; plain-secret compares hash both
  sides first so length does not leak; the JWT check requires alg HS256 (refuses none), aud (string or array), exp,
  nbf, dest (valid myshopify shop) and checks iss against dest when present; everything missing fails closed.
- Criteria: added rows for the cancel-before-verify edge case, the two audit entries, "never asks for a password or
  API token", HMAC/JWT edge cases, fixed error codes.
- CLAUDE.md: UTC times, never-delete (only status changes; tokens removed as secrets), no .env read, nothing
  downloaded.

## 7. Execution log (2026-10-29)

- D37 = A (pure parts only), D39 = compare-and-swap. Specs 08/09 still missing, so no Store, functions, notifier,
  spec 09 token change or smoke script yet; no spec 08/09 file was created or changed.
- Built: money_text.ts, shopify_auth.ts (OAuth HMAC, webhook HMAC, session-token JWT, constantTimeEqual, spec 05
  shop-domain rules), shopify_orders.ts (+ ORDER_QUERY), shopify_client.ts (ShopifyClient, FetchShopifyClient with
  fixed error codes, TokenStore interface + withFreshToken), fake_shopify.ts; tests for each.
- withFreshToken takes a small TokenStore interface (get / swap / setStoreLastError) - spec 12's store implements it.
- Byte arrays are typed Uint8Array<ArrayBuffer> (needed by the current TypeScript for Web Crypto).
- Results: deno test 48 passed (13 match_rules + 35 new); deno check, lint, fmt --check clean; no logging, no remote
  imports, no real-looking Shopify tokens, no .env files.
