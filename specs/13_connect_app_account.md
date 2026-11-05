# 13 Connect the app account and the pay page to the real server

Purpose
Make the app's login, business, wallets, Shopify and alerts work against the real Supabase backend,
and make the customer pay page call the real pay-session API. After this spec, everything except the
phone-to-server SMS pipeline (spec 13a) runs on real data.

Scope
Flutter app:
- Packages: supabase_flutter and url_launcher, exact pinned versions (ask me first).
- Configuration through --dart-define only: SUPABASE_URL and SUPABASE_ANON_KEY. FUNCTIONS_URL =
  SUPABASE_URL + "/functions/v1". Nothing is hard-coded. If a value is missing, the app shows one screen
  "অ্যাপ কনফিগার করা হয়নি" and nothing else.
- Thin gateways in lib/data/supabase/ so repositories can be tested with fakes:
  AuthGateway (OTP send/verify, current user, sign out), TableGateway (merchants and wallets select /
  insert / update), FunctionsGateway (call an Edge Function with the user token).
- Real repositories: SupabaseAuthRepository, SupabaseWalletRepository, SupabaseStoreRepository,
  SupabaseAlertsRepository (new). providers.dart uses them when the app runs; tests keep the mocks.
- New small UI pieces in the existing style:
  - Alerts card on হোম (rule 6).
  - Shopify "আবার যুক্ত করুন" state and a "সেটআপ গাইড" section in সেটিংস (rule 5).
  - "বিচ্ছিন্ন করুন" shows instructions instead of disconnecting (rule 5).
- Local Supabase email: supabase/config.toml gets 6-digit email OTP, and a Bangla email template file
  supabase/templates/otp_bn.html that shows the code ({{ .Token }}) and no link.
Pay page:
- pay_page/api.real.js implementing the spec 07 API with the spec 09 pay-session function.
- pay_page/config.js: API_BASE (the functions URL) and USE_MOCK (default false). The CSP connect-src in
  index.html lists the API origin.
Not in scope: device keys, SMS upload, heartbeat, sms-status, claim-review, rule updates and device
deactivate (all spec 13a); deploying anything (spec 15); new Edge Functions or tables.

Contract
AuthRepository (spec 05 interface, real behaviour):
- sendCode(email): Supabase email OTP with user creation allowed. Supabase "rate limit" errors -> tooSoon;
  no network -> offline; bad email -> invalidEmail. The 60-second resend wait in the app stays.
- verifyCode(email, code): verify the email OTP. Wrong or expired code -> wrongCode.
  After success: select the merchant owned by this user; none -> needsBusinessName; found -> signedIn.
- createMerchant(name): insert into merchants (owner_id = current user) -> signedIn.
- signOut(): Supabase sign out (spec 13a adds device deactivate before it).
- The session stays signed in across app restarts (supabase_flutter session storage).
- AuthState.deviceId stays null until spec 13a.

WalletRepository (real): reads and writes the wallets table (RLS limits it to the merchant).
- The app validates first with the spec 05 validators.
- Database unique (operator, wallet_number) -> duplicate; database sim partial unique -> simTaken;
  check violation -> invalidNumber; no network -> show "ইন্টারনেট নেই" and change nothing.
- watch() refetches after every write and when the app comes to the front.
- Still no delete.

StoreRepository (real):
- watch(): calls shopify-status after sign-in, when the app comes to the front, and every 3 seconds for
  up to 60 seconds after a connect link was opened (stops as soon as connected).
- connectShopify(domain): calls shopify-connect-link, opens the returned URL in the external browser
  (url_launcher). Results: done (link opened), invalidDomain, offline, and new: shopTaken
  ("এই স্টোর অন্য একটি BDPay অ্যাকাউন্টে যুক্ত"). Add shopTaken to ConnectResult.
- testConnection(): shopify-status connected.
- disconnect() is removed from the interface (see rule 5).
- ShopifyStore gets lastError (String?) so the UI can show reconnectNeeded.

AlertsRepository (new, lib/domain/repositories): Stream<List<AppAlert>> watch(); refresh().
AppAlert: id, kind, openedAt, title, hint (from alerts-list). Refreshed after sign-in, when the app comes
to the front, and every 5 minutes while open.

Pay page api.real.js:
- getSession / getStatus: GET API_BASE/pay-session?t=TOKEN. 200 -> Session; 404 -> {error: "notFound"};
  429 -> treat as a network wait (keep the current screen, retry at the next poll).
- submitClaim: POST API_BASE/pay-session {token, operator, trxId}. 200 -> {result, session};
  429 -> {result: "rateLimited"}; 404 -> {result: "notFound"}.
- 10-second timeout; any other failure -> the spec 07 network error message.
- textContent rule from spec 07 still applies.

Functional rules
1. Login uses the existing spec 05 screens; only the repository changes.
2. A user who signs in on a second phone sees the same merchant, wallets and Shopify state.
3. Wallet rows show exactly what the database holds; after an error the form keeps the typed values.
4. After returning from the browser, the Shopify section shows "যুক্ত হচ্ছে…" until shopify-status says
   connected (then the normal connected view) or 60 seconds pass (then "এখনো যুক্ত হয়নি — আবার চেষ্টা করুন").
5. Shopify section changes:
   - lastError reconnectNeeded -> amber line "Shopify-এর সংযোগ শেষ হয়ে গেছে" and the primary button
     "আবার যুক্ত করুন" (same connect flow).
   - "বিচ্ছিন্ন করুন" opens a sheet: "Shopify বিচ্ছিন্ন করতে: Shopify অ্যাডমিন > Apps > BDPay > Uninstall.
     এরপর নতুন অর্ডার আর যাচাই হবে না।" with "ঠিক আছে".
   - "সেটআপ গাইড" (collapsible, shown when connected): the steps from shopify_app/MERCHANT_SETUP_BN.txt,
     copied into strings.dart.
6. Alerts card on হোম (below the setup card, above the device card): one red-bordered card per open alert
   with its title and hint, newest first. Hidden when there are none. Tapping does nothing in v1.
7. The setup card (spec 05) now reads real wallets and the real Shopify status.

Edge cases
- Email OTP expired -> wrongCode text.
- The app is killed during the business name step -> on next start the user is signed in without a merchant
  -> business name screen again.
- Adding a wallet number another merchant already uses -> duplicate (the database rule is global).
- No network while saving a wallet -> nothing saved, "ইন্টারনেট নেই".
- The merchant opens the connect link but closes the browser -> after 60 s the "এখনো যুক্ত হয়নি" text.
- The pay page API answers 500 -> network error message, form stays filled.
- The pay page served from an origin not in PAY_PAGE_ORIGIN -> the browser blocks the call (expected;
  documented in the smoke steps).

Non-functional rules
- No anon key, URL or token is written in source files or logs.
- Screens still talk only to repository interfaces.
- flutter analyze reports zero issues; deno tests for the pay page still pass.

Acceptance criteria
- flutter analyze: no issues. flutter test passes (all earlier tests with mocks still pass).
- New unit tests with fake gateways: every AuthResult mapping; merchant found vs needsBusinessName;
  wallet duplicate / simTaken / invalidNumber mapping; StoreRepository polling stops when connected and
  after 60 s; shopTaken mapping; alerts refresh.
- New widget tests: reconnectNeeded view; disconnect instructions sheet; setup guide shown only when
  connected; alerts card shows two alerts newest first and is hidden when empty; missing dart-define
  shows "অ্যাপ কনফিগার করা হয়নি".
- deno test pay_page/tests passes, with new tests for api.real.js using a stub fetch: 200, 404, 429 on GET
  and POST, timeout, 500.
- flutter build apk --debug with the dart-defines succeeds.
- Manual checks on the emulator against local Supabase (Claude Code gives me exact commands; the emulator
  reaches the host at 10.0.2.2):
  1. Sign in with a new email; read the 6-digit code in the local mail viewer (Mailpit/Inbucket on port 54324);
     enter the business name; the merchants row appears in Studio.
  2. Add a bKash wallet; the row appears in Studio; adding the same number again shows the duplicate text.
  3. Sign out and in again; the wallet is still there.
  4. Tap "Shopify যুক্ত করুন" with a test shop; the browser opens a Shopify authorize URL for that shop.
  5. Pay page against local functions: a session from smoke_match.ts opens, a TrxID submit works, and after
     the smoke device sends the SMS the page shows "পেমেন্ট নিশ্চিত হয়েছে".

Assumptions
- Specs 01 to 12a are done; local Supabase is running with the spec 12 schema and seed.
- The full Shopify connect (browser -> Shopify -> back) needs a public functions URL and is tested in spec 14.
