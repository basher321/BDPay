# 17 Store connections (all platforms)

Purpose
Merchants sell on many website platforms, not only Shopify. One common Settings section lets a merchant
connect their website from a platform list. Shopify keeps its OAuth connection (spec 10). Every other
platform uses one common BDPay Merchant API: the website asks BDPay for a pay link per order, and BDPay
tells the website when the payment is verified. The platform choice only selects the setup guide.

Platforms (fixed values; Dart enum, TypeScript string union, SQL CHECK list; shown name in brackets)
shopify (Shopify), wordpress (WordPress / WooCommerce), webflow (Webflow), framer (Framer),
wix (Wix Studio), squarespace (Squarespace), bubble (Bubble), drupal (Drupal), joomla (Joomla),
hubspot (HubSpot CMS), duda (Duda), react (React.js), nextjs (Next.js), vue (Vue.js), laravel (Laravel),
nodejs (Node.js), django (Django), ghost (Ghost), magento (Magento), prestashop (PrestaShop),
webstudio (Webstudio), astro (Astro), sveltekit (SvelteKit), nuxt (Nuxt.js), other (অন্য প্ল্যাটফর্ম).
Platform names are brand names and stay in English; every other text is Bangla from the ARB file.
Connection kind: shopify -> oauth; every other platform -> api.

Scope
Flutter app (app/):
- Settings: the "Shopify স্টোর" section becomes "স্টোর / ওয়েবসাইট". It lists the merchant's connections
  (platform name, site name, status chip) and has a "+ স্টোর যোগ করুন" button.
- Add flow (bottom sheet, same style as the wallet sheet):
  1. Platform picker: a searchable list of the platforms above.
  2. Shopify -> the sheet closes with a toast pointing to the "Shopify স্টোর" section (spec 13 flow,
     unchanged), which stays as its own section right below.
  3. Any other platform -> site name (2 to 60 characters) and site URL (https only) -> "যুক্ত করুন".
     The result screen shows the API key ONCE with a copy button and the line
     "এই কী আর দেখানো হবে না — এখনই কপি করে নিরাপদে রাখুন", the webhook secret ONCE the same way,
     and the setup guide for that platform.
- Connection detail (tap a row): platform, site name, site URL, webhook URL (editable), key prefix
  (for example "bdp_live_3f9a…"), connected time, "নতুন কী তৈরি করুন" (rotate: the old key stops working
  at once; confirm dialog first), "সংযোগ বন্ধ করুন" (disable; confirm dialog; new orders are refused,
  existing sessions and records stay), and the setup guide.
- Setup guide per platform: short Bangla steps. Server platforms (wordpress, drupal, joomla, magento,
  prestashop, laravel, nodejs, django, nextjs, nuxt, sveltekit, astro, ghost, react, vue) call the API
  from their server code. Site builders (webflow, framer, wix, squarespace, bubble, hubspot, duda,
  webstudio) call it from their backend or automation feature (for example Wix Velo, Bubble API
  Connector, HubSpot serverless functions, Webflow/Framer/Squarespace/Duda/Webstudio through an
  automation service). React and Vue guides say the key must stay on a server, never in browser code.
- StoreRepository gains the calls in Contract; the mock implements them for tests and the demo build.
- All new text in app_bn.arb. Colours and styles only from the theme. Screens use only repositories.
Edge Functions (supabase/functions/, TypeScript, Deno, handlers use only the Store interface):
- store-connections (Supabase user token): list, create, update, rotate key, disable.
- merchant-api (BDPay API key): create a checkout, read a checkout status.
- WebhookNotifier: plugged into spec 09 like ShopifyNotifier; tells the merchant's site about a verified
  payment. Retries use the existing order_syncs queue and shopify-sync's retry timing, run by a new
  store-webhooks-sync cron function (X-Cron-Secret).
Database (one new numbered migration):
- stores: platform CHECK list extended to the values above; shop_domain may be null for api
  connections (the myshopify.com check applies only to shopify); new columns site_name, site_url,
  webhook_url, api_key_prefix, api_key_hash (SHA-256 of the key), secret_version; status adds
  'disabled'. One active Shopify store per merchant (as before); one active API connection per
  merchant + platform + site_url. The cron helper gains store-webhooks-sync (every 5 minutes).
- RLS on stores unchanged: a merchant sees only its own rows; key hashes and secret ids are never
  selectable by the app (the app reads through store-connections only).
Not in scope: ready-made plugins (WooCommerce plugin, Wix app, etc.), marketplace connections (Daraz and
similar do not allow outside payment methods), refunds, the web dashboard, the missing spec 10 Shopify
functions (separate step 10b).

Contract
StoreConnection (Dart model and TypeScript type): id, platform, kind (oauth | api), siteName, siteUrl,
webhookUrl (or null), apiKeyPrefix (or null), status (active | disabled | uninstalled), lastError (or null),
connectedAt.
StoreRepository additions:
  watchConnections() -> Stream<List<StoreConnection>>
  createApiConnection(platform, siteName, siteUrl) -> CreateResult {done(connection, apiKey, webhookSecret),
      invalidName, invalidUrl, duplicate, offline}
  updateWebhookUrl(id, url) -> invalidUrl | done | offline
  rotateKey(id) -> done(apiKey) | offline
  disable(id) -> done | offline

1. store-connections (Supabase user token; the user owns a merchant)
   GET -> 200 {ok, connections: StoreConnection[]}
   POST {action: "create", platform, siteName, siteUrl} -> 200 {ok, connection, apiKey, webhookSecret}
     platform shopify -> 400 useShopifyConnect; bad name -> 400 invalidName; non-https or bad URL ->
     400 invalidUrl; same platform + siteUrl already active -> 409 duplicate.
   POST {action: "updateWebhook", id, webhookUrl} -> 200 {ok, connection}  (https only, else 400 invalidUrl)
   POST {action: "rotateKey", id} -> 200 {ok, apiKey}
   POST {action: "disable", id} -> 200 {ok, connection}
   Another merchant's id -> 404 notFound. Audit entries: store.create, store.rotateKey, store.disable,
   store.updateWebhook.
   API key: "bdp_live_" + 32 random bytes base64url. Only SHA-256(key) and the first 12 characters are stored.
   Webhook secret: "whsec_" + base64url(HMAC-SHA256(PAY_TOKEN_SECRET, "webhook:" + id + ":" + secret_version)),
   recomputed when needed and never stored.
   Pay token of an API order: base64url(HMAC-SHA256(PAY_TOKEN_SECRET, "api-order:" + id + ":" + orderId)),
   so the same order always gets the same pay link; only SHA-256(token) is stored (spec 09 rule).
   PAY_TOKEN_SECRET or PAY_PAGE_URL missing -> 503 storeNotReady (fails closed).

2. merchant-api (header Authorization: Bearer <API key>; wrong, rotated or disabled key -> 401 badApiKey)
   POST /checkouts {orderId (1-100 chars), orderRef (1-40 chars, shown to the customer),
     amountPoisha (integer > 0), currency "BDT", returnUrl (https)} -> 200 {ok, checkoutId, payUrl, status}
     Idempotent on (connection, orderId): the same orderId returns the first session and its pay link;
     a different amount for the same orderId -> 409 orderChanged. Wrong currency -> 400 wrongCurrency;
     a float or text amount -> 400 badAmount.
   GET /checkouts/{orderId} -> 200 {ok, checkoutId, orderId, amountPoisha, status} (spec 09 session
     status: open, pending, verified, mismatch, expired, rejected) | 404 notFound.
   CORS: none (server-to-server only). Rate limit 60 per minute per connection.
   The pay link and the customer page are the existing spec 07/09 pay page; nothing new for the customer.

3. WebhookNotifier.onSessionVerified(session) (session of an api connection with a webhook URL)
   POST webhookUrl, JSON {event: "payment.verified", checkoutId, orderId, orderRef, amountPoisha,
     verifiedAt}, headers X-BDPay-Timestamp (Unix seconds), X-BDPay-Signature =
     hex(HMAC-SHA256(webhook secret, timestamp + "." + raw body)), X-BDPay-Event-Id (unique; the site ignores
     a repeated id). Redirects are not followed.
   2xx -> done. Other answer or no answer in 10 s -> pending, retry with the spec 10 waits; after 24
   attempts -> failed (the spec 11 alert is raised when alerts-check exists). No webhook URL -> nothing sent
   (the site polls GET /checkouts).
   A webhook failure never changes the BDPay payment result.

Functional rules
1. BDPay decides "paid" only on the server (spec 09). The website learns it from the webhook or GET.
2. The API key and webhook secret are shown once, never logged, never returned again. Lost key -> rotate.
3. Money is integer poisha in the API. "1250.00 taka" is sent as 125000.
4. A disabled connection refuses new checkouts (401); existing sessions finish normally.
5. Connections, sessions and audit entries are never deleted.
6. SMS and order text from websites is untrusted: shown only as plain text.

Edge cases
- The site sends the same order twice (double click, retry) -> one session, same pay link.
- The site changes the amount for an order already sent -> 409 orderChanged.
- The key is rotated while orders are open -> open sessions still finish; new calls need the new key.
- The webhook URL is down for a day -> retries, then failed + alert; GET /checkouts still answers.
- Two merchants add the same site URL -> both allowed (BDPay cannot prove site ownership; each has its own key).
- The merchant picks Shopify in the list -> the spec 13 Shopify flow, not an API key.

Non-functional rules
- Never log API keys, webhook secrets, webhook bodies, customer data or TrxIDs.
- Handlers use only the Store interface. deno check, deno lint and deno fmt --check pass.
- flutter analyze has no issues.

Acceptance criteria
- deno test: create/list/update/rotate/disable, each 400/404/409; another merchant's connection is
  invisible; key hash only stored; checkout create + idempotency + orderChanged + wrongCurrency + badAmount;
  bad / rotated / disabled key 401; GET status; webhook signature correct; retry schedule; failure after 24
  attempts; a failed webhook leaves the session verified. Specs 08 to 12 tests still pass.
- SQL tests: new migration applies on top of the old ones; RLS hides other merchants' rows; existing
  Shopify rows still valid.
- Flutter unit + widget tests: platform picker search; Shopify still opens its own form; api create shows
  the key once and copy works; rotate and disable confirm dialogs; errors per result; mock repository.
- Manual on the real server: add a "Laravel" connection, create a checkout with curl, pay through the pay
  page with a Dev Lab SMS, see the session verified and the webhook received by a test endpoint.

Assumptions
- Specs 01 to 16 are done; the Shopify server functions of spec 10 are a separate step (10b).
- The owner approved (2026-11-07) one new migration that replaces CHECK constraints and the
  stores_one_active index on stores (DROP CONSTRAINT / DROP INDEX + new ones; no table, column or data removed).
- Env for the functions: PAY_TOKEN_SECRET and PAY_PAGE_URL (already in the spec 14/15 runbooks).
