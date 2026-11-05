# 10a Shopify app config and checkout extension

Purpose
Show the customer a clear "pay now" box on Shopify's Thank-you page and Order status page for
BDPay orders, with a button that opens the BDPay pay page (spec 07). After payment the same box
shows "payment confirmed". This is how every customer reaches the pay page.

Scope
- A new folder shopify_app/ made with the Shopify CLI as an extension-only app:
  - shopify.app.toml: app name BDPay, embedded false, scopes read_orders,write_orders,
    redirect URL FUNCTIONS_URL/shopify-oauth-callback, webhooks (below).
  - extensions/bdpay-pay-box/: one checkout UI extension (Preact + Shopify web components,
    API version 2026-10) with two targets: the Thank-you page block and the Order status page block.
    Use the exact target names the current Shopify CLI template and docs give.
  - extensions/bdpay-pay-box/locales/: en.default.json (English) and bn.json (Bangla).
  - extensions/bdpay-pay-box/src/view_logic.ts: pure logic (no Shopify imports) for tests.
  - shopify_app/MERCHANT_SETUP_BN.txt: the merchant setup steps in Bangla (reused in spec 13).
- Deno tests for view_logic.ts in shopify_app/tests/.
- Add one line to CLAUDE.md under Folders: "- shopify_app/    Shopify app config and checkout extension".
- Not in scope: any backend change (spec 10 already has shopify-paylink), an admin page inside
  Shopify, a Shopify App Store listing, deploying the app (I do that by hand), app screen changes (spec 13).

Contract
shopify.app.toml webhooks (api_version 2026-10, uri = FUNCTIONS_URL/shopify-webhooks):
- topics orders/create, orders/cancelled, app/uninstalled, with include_fields limited to
  id and admin_graphql_api_id (BDPay reads the order itself with GraphQL; it never needs customer data
  from the webhook). If the CLI does not allow include_fields for a topic, tell me.
- compliance topics customers/data_request, customers/redact, shop/redact.
- The install must go through the backend OAuth redirect from spec 10 (authorization code grant).
  If the current CLI needs a specific setting for that (for example a legacy install flow flag),
  tell me before setting it.
- client_id, FUNCTIONS_URL and application_url are placeholders written as REPLACE_ME_...;
  I fill them with "shopify app config link". No secret is ever written in this folder.

shopify.extension.toml: capabilities network_access = true. No other capability.

The extension calls spec 10's shopify-paylink:
  POST FUNCTIONS_URL/shopify-paylink with Authorization: Bearer <await shopify.sessionToken.get()>,
  body {orderId}. Get a fresh session token before every call (Shopify caches it).
Order id: Thank-you page from the order confirmation API; Order status page from the order API.
FUNCTIONS_URL is a constant in one file (src/config.ts) with a REPLACE_ME value.

view_logic.ts (pure):
  type PaylinkResult = {status: "ready", payUrl, sessionStatus} | {status: "notBdpay"} |
                       {status: "alreadyPaid"} | {status: "notReady"} | {status: "error"}
  decideView(result, attempt) -> "hidden" | "loading" | "payNow" | "pending" | "paid" | "waitLonger" | "failed"
  nextRetryDelay(attempt) -> milliseconds or null
  Rules:
    notBdpay -> hidden.
    alreadyPaid -> paid. ready + sessionStatus verified -> paid.
    ready + sessionStatus open -> payNow.
    ready + sessionStatus pending or mismatch -> pending.
    ready + sessionStatus expired or rejected -> hidden (the pay page explains those cases).
    notReady -> loading while attempt < 10 (retry every 3000 ms), then waitLonger (no more retries).
    error -> loading for attempts 0 and 1 (retry after 3000 ms), then failed.

Functional rules
- Views (all text from the locale files; Bangla shown here, English in en.default.json):
  hidden: nothing is shown at all.
  loading: a small spinner, no text.
  payNow: an info banner, heading "bKash / Nagad দিয়ে পেমেন্ট সম্পন্ন করুন", text
    "অর্ডার নিশ্চিত করতে এখনই পেমেন্ট করুন এবং TrxID দিন।", and a primary button
    "এখনই পেমেন্ট করুন" that opens payUrl.
  pending: an info banner "পেমেন্ট যাচাই হচ্ছে" with a plain link "অবস্থা দেখুন" to payUrl.
  paid: a success banner "পেমেন্ট নিশ্চিত হয়েছে ✓". No button.
  waitLonger: text "পেমেন্ট লিংক তৈরি হচ্ছে — একটু পরে পেজটি রিফ্রেশ করুন".
  failed: text "পেমেন্ট লিংক লোড হয়নি — পেজটি রিফ্রেশ করুন".
- The extension shows nothing for orders that are not BDPay orders, so it is safe to place on every store.
- The extension never shows the wallet number, the amount or the TrxID form itself; those live on the
  pay page only.
- No data is stored by the extension.
- MERCHANT_SETUP_BN.txt has these numbered steps:
  1. BDPay অ্যাপে Shopify যুক্ত করুন (সেটিংস > Shopify স্টোর).
  2. Shopify অ্যাডমিন > Settings > Payments > Manual payment methods > Create custom payment method.
     নামে অবশ্যই "BDPay" শব্দটি রাখুন, যেমন: "bKash / Nagad (BDPay)".
  3. Shopify অ্যাডমিন > Settings > Checkout > Customize: Thank you পেজে এবং Order status পেজে
     "BDPay pay box" ব্লক যোগ করে Save করুন.
  4. স্টোরের মুদ্রা BDT রাখুন.
  5. একটি পরীক্ষামূলক অর্ডার দিয়ে দেখুন "এখনই পেমেন্ট করুন" বোতাম দেখা যাচ্ছে কিনা.
  Mark the file "Check the Shopify menu names before release; they may change."

Edge cases
- Thank-you page opens before Shopify finishes creating the order -> notReady -> retries -> payNow.
- The customer comes back days later through the order email -> Order status page shows the current state.
- A card or COD order -> hidden.
- The merchant has not connected Shopify to BDPay yet -> the backend answers notBdpay -> hidden.
- Session token expired between retries -> a fresh token is fetched before each call.
- Network failure -> two quick retries, then failed text (never a broken box).

Non-functional rules
- The extension bundle stays within Shopify's size limit; use only Preact and Shopify's UI packages.
- No third-party scripts, analytics or tracking.
- view_logic.ts has no imports so Deno can test it.

Acceptance criteria
- deno test shopify_app/tests passes: every decideView rule above, including notReady at attempts 0, 9, 10
  and error at attempts 0, 1, 2; nextRetryDelay returns null when no retry is due.
- The extension builds with the Shopify CLI build command with no errors or type errors.
- A search of shopify_app shows no secret, token, API key value or real URL (only REPLACE_ME placeholders).
- en.default.json and bn.json have the same keys.
- I check by hand: "shopify app dev" on my development store shows the box in the checkout editor
  preview on both pages; with src/config.ts pointing at a fake answer (a DEV_FAKE switch in config.ts,
  default off), each view can be seen once.
- The full live test (real order -> pay -> paid box) happens in spec 14 after the backend is deployed.

Assumptions
- Specs 10 is done.
- I have a Shopify Partner account and a development store, and Node.js is installed for the Shopify CLI.
- I will request network access for the extension in the Partner Dashboard (API access requests ->
  Allow network access in checkout UI extensions).
- If Shopify asks for a protected customer data request for order webhooks, I will file it, stating
  that BDPay reads only the order id, name, payment gateway names, financial status and amount.
