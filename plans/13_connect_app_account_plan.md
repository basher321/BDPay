# Plan 13 - Connect the app account and the pay page to the real server

Spec: specs/13_connect_app_account.md. Written 2026-10-30.
Read with: CLAUDE.md, specs 05, 07, 09, 10, 11 and 13, and the current code in app/ (Flutter, ARB strings,
Riverpod providers, mock repositories) and pay_page/.

Reviewed 2026-10-30 against the spec and CLAUDE.md; section 9 lists what the review changed.

Default rule: until you answer a decision below, the build follows the spec text; where the spec cannot work as
written (section 0, D130-D134) I stop and ask.

## 0. Blockers - what spec 13 assumes vs what exists today

| Spec 13 assumes | Today | Effect |
|---|---|---|
| Specs 01-12a done; local Supabase running with spec 12 schema and seed | No Docker / Supabase CLI, no migrations (spec 12 waits for a database login), no PgStore (12a waits for your supabase-js yes) | The app and pay page have nothing real to talk to; every manual emulator check waits |
| Edge Functions pay-session (09), shopify-connect-link and shopify-status (10), alerts-list (11) | None of them exist (only spec 08's four device functions) | FunctionsGateway can be written and unit-tested with fakes, never called for real |
| smoke_match.ts (manual check 5) | Does not exist (spec 09) | Manual check 5 waits |
| supabase/config.toml (6-digit OTP, template) | Does not exist (needs `supabase init`, spec 12 D86) | config.toml changes wait; the template file can be written now |

- D130. **Build order.** Options: A (recommended) build what needs no backend now - packages (after your yes),
  gateways with fakes, the four repositories, the UI pieces, api.real.js with a stub fetch, all unit / widget / deno
  tests, `flutter build apk --debug`, the OTP template - and leave config.toml and the manual emulator checks until
  specs 09-12a run on local Supabase; B wait for everything.

Everything in sections 1-5 is testable without a backend except where marked "needs backend".

## 1. Files

Marked [CHANGED 05], [CHANGED 07] etc. = an earlier spec's file.

### Flutter - new (app/lib/)
- core/app_config.dart - reads SUPABASE_URL / SUPABASE_ANON_KEY from `String.fromEnvironment`; functionsUrl =
  SUPABASE_URL + "/functions/v1"; isComplete. No default values.
- data/supabase/auth_gateway.dart - AuthGateway interface + SupabaseAuthGateway: sendOtp(email), verifyOtp(email,
  code), currentUserId / email, onAuthChange stream, signOut.
- data/supabase/table_gateway.dart - TableGateway interface + SupabaseTableGateway: merchants and wallets only, as
  the spec says - merchantForUser(userId), insertMerchant(name), listWallets(), insertWallet(row),
  updateWallet(id, fields). (A stores read is added only if you choose D133 A.)
- data/supabase/functions_gateway.dart - FunctionsGateway interface + SupabaseFunctionsGateway: call(name, {method,
  body}) with the user token -> FunctionsReply {status, json} or throws OfflineException.
- data/supabase/gateway_errors.dart - OfflineException, GatewayError(code) and the mapping helpers of section 3.
- data/supabase/supabase_auth_repository.dart - AuthRepository on AuthGateway + TableGateway.
- data/supabase/supabase_wallet_repository.dart - WalletRepository on TableGateway (validators first).
- data/supabase/supabase_store_repository.dart - StoreRepository on FunctionsGateway + url opener; polling.
- data/supabase/supabase_alerts_repository.dart - AlertsRepository on FunctionsGateway (alerts-list); 5-minute
  refresh.
- data/supabase/app_lifecycle.dart - one "app came to the front" stream (AppLifecycleListener) that the
  repositories listen to, injectable for tests.
- data/supabase/url_opener.dart - UrlOpener interface + UrlLauncherOpener (launchUrl in external-application mode
  only, no canLaunchUrl, so no manifest <queries> entry is needed); the URL (it carries Shopify's state value) is
  never logged; fake in tests.
- data/supabase/timers.dart - a small injectable Timers interface (periodic / delay) so the 3 s / 60 s / 5 min
  rules are unit-tested with a fake, without adding the fake_async package.
- data/mock/mock_alerts_repository.dart - mock AlertsRepository for tests and the mock app (none open; tests set
  alerts).
- domain/repositories/alerts_repository.dart - AlertsRepository: watch(), refresh().
- domain/models/app_alert.dart - AppAlert {id, kind, openedAt (UTC), title, hint}.
- features/home/widgets/alerts_card.dart - red-bordered card per open alert, newest first; hidden when none.
- features/settings/widgets/shopify_setup_guide.dart - collapsible "সেটআপ গাইড" (connected only).
- features/settings/widgets/shopify_disconnect_sheet.dart - the instructions sheet with "ঠিক আছে".
- shell/not_configured_screen.dart - the single "অ্যাপ কনফিগার করা হয়নি" screen.

### Flutter - changed
- [CHANGED 01] pubspec.yaml - supabase_flutter and url_launcher, exact versions (section 2).
- [CHANGED 01] lib/main.dart - if AppConfig incomplete -> run NotConfiguredScreen only; else Supabase.initialize
  with debug: false (no request / auth logging), then the app. main.dart is not a screen; it is the only file
  besides lib/data/supabase/ that imports supabase_flutter.
- [CHANGED 05] lib/data/account_providers.dart - real repositories when the app runs; mocks stay for tests (tests
  already override mockAccountDataProvider; a new `useMockAccountProvider` override keeps every earlier test on mocks);
  alertsRepositoryProvider + alertsProvider.
- [CHANGED 05] lib/domain/account_enums.dart - ConnectResult.shopTaken (spec); AddWalletResult.offline only with
  D131 = yes.
- [CHANGED 05] lib/domain/models/shopify_store.dart - lastError (String?).
- [CHANGED 05] lib/domain/repositories/store_repository.dart - disconnect() removed.
- [CHANGED 05] lib/data/mock/mock_shopify_repository.dart - no disconnect(); lastError support for tests.
- [CHANGED 05] lib/features/settings/widgets/shopify_section.dart - "যুক্ত হচ্ছে…" polling state, 60-second "এখনো
  যুক্ত হয়নি" text, reconnectNeeded amber line + "আবার যুক্ত করুন", disconnect sheet instead of the confirm dialog,
  setup guide, shopTaken error.
- [CHANGED 05] lib/features/settings/widgets/wallet_sheet.dart and wallets_section.dart - show "ইন্টারনেট নেই" for
  offline; keep the typed values after any error.
- [CHANGED 02/05] lib/features/home/home_screen.dart - AlertsCard between the setup card and the device card.
- [CHANGED 05] lib/features/home/setup_status.dart - unchanged logic, now fed by the real providers (no code change
  expected; listed for review).
- [CHANGED 01] lib/l10n/app_bn.arb (+ generated app_localizations*.dart) - every new text, incl. the setup guide
  steps (D132: ARB, not strings.dart).
- [CHANGED 01, only with D134 = yes] android/app/src/debug/res/xml/network_security_config.xml (new) + the debug
  manifest - cleartext allowed only to 10.0.2.2 and only in debug builds. The main manifest is not changed.

### Flutter tests - new (app/test/)
- data/supabase/fakes.dart - FakeAuthGateway, FakeTableGateway, FakeFunctionsGateway, FakeUrlOpener, fake
  lifecycle stream.
- data/supabase/supabase_auth_repository_test.dart, supabase_wallet_repository_test.dart,
  supabase_store_repository_test.dart (fake Timers for the 3 s / 60 s polling), supabase_alerts_repository_test.dart.
- features/settings/shopify_connect_polling_test.dart - rule 4: "যুক্ত হচ্ছে…" after the link opens, the connected
  view when status says connected, "এখনো যুক্ত হয়নি — আবার চেষ্টা করুন" after 60 s.
- features/settings/wallet_sheet_errors_test.dart - rule 3: after duplicate / simTaken / invalidNumber (/ offline)
  the sheet keeps the typed values.
- features/home/home_order_test.dart - rule 6 position (setup card, then alerts card, then device card) and rule 7
  (setup card fed by the wallet and store providers).
- secrets_and_boundaries_test.dart - reads the lib/ sources: supabase_flutter imported only in lib/data/supabase/
  and lib/main.dart; url_launcher only in url_opener.dart; no print / debugPrint / log calls that take auth,
  token, URL or email values; no JWT-shaped string anywhere in lib/ or test/.
- core/app_config_test.dart.
- features/home/alerts_card_test.dart; features/settings/shopify_reconnect_test.dart,
  shopify_disconnect_sheet_test.dart, shopify_setup_guide_test.dart; shell/not_configured_screen_test.dart.
- [CHANGED 05] existing tests that tap "বিচ্ছিন্ন করুন" and expect the confirm dialog follow rule 5 (D135).

### Supabase - new
- supabase/templates/otp_bn.html - Bangla email with {{ .Token }}, no link, inline styles only.
- supabase/config.toml - needs backend: after `supabase init` (your yes) - [auth.email] otp_length = 6,
  otp_expiry, enable_confirmations as needed, and both the magic_link and confirmation templates pointing at
  ./templates/otp_bn.html (D136).

### Pay page
- pay_page/api.real.js (new) - getSession / getStatus / submitClaim on pay-session with fetch; `createRealApi({
  base, fetch, timeoutMs })` so tests inject a stub fetch.
- [CHANGED 07] pay_page/config.js - API_BASE and USE_MOCK (default false), replacing API / API_ORIGIN. Shipped
  with API_BASE = "" (D145): the spec puts the functions URL in this file, so it is the one place a URL may live;
  I do not write the local value - you set it for manual check 5.
- [CHANGED 07] pay_page/api.js - picks api.mock.js when USE_MOCK, else api.real.js; the NetworkError wrapper stays.
- [CHANGED 07] pay_page/index.html - CSP connect-src 'self' + the API origin (D137, D145); the existing
  require-trusted-types-for 'script' stays.
- pay_page/tests/api_real_test.js (new) - stub fetch: GET 200 / 404 / 429 / 500 / timeout; POST 200 / 404 / 429 /
  500 / timeout; empty API_BASE -> NetworkError; the token is URL-encoded in the GET; no console output (the stub
  records none). No innerHTML-style use (search stays).

## 2. Packages (asked before adding)

Newest stable releases at least two weeks old today (2026-10-30), from pub.dev:

| Package | Exact version | Published | Why |
|---|---|---|---|
| supabase_flutter | 2.18.3 | 2026-10-12 | auth (email OTP, session restore), tables, functions |
| url_launcher | 6.3.3 | 2026-10-02 | open the Shopify connect link in the external browser |

pubspec gets `supabase_flutter: 2.18.3` and `url_launcher: 6.3.3` (no ^). supabase_flutter brings in its own
dependencies (supabase, app_links, http, shared_preferences, url_launcher, passkeys_platform_interface, ...), which
pubspec.lock pins. `flutter pub get` downloads them - your yes first. No other package: timing is tested with the injectable Timers, not fake_async (importing a transitive
dependency directly would mean adding it to pubspec).

## 3. Error mapping

### Auth (AuthGateway -> AuthResult)
| Gateway outcome | sendCode | verifyCode |
|---|---|---|
| email fails isValidEmail (checked before any call) | invalidEmail | - |
| AuthException status 400 / code email_address_invalid or validation_failed | invalidEmail | wrongCode |
| AuthException status 429 / code over_email_send_rate_limit or over_request_rate_limit | tooSoon | tooSoon |
| AuthException code otp_expired, invalid_credentials, or status 401 / 403 | - | wrongCode |
| SocketException / ClientException / AuthRetryableFetchException / TimeoutException | offline | offline |
| success | done (codeSent) | then merchantForUser: found -> signedIn, none -> needsBusinessName |
| anything else | offline (shown as "ইন্টারনেট নেই"; logged as the error type only) | wrongCode (D138) |

The app's own 60-second resend wait stays in front of all of this. Nothing in this table is logged except the
error's type name (AuthException, PostgrestException code, HTTP status); never its message (it can hold the email),
the email, the code, the token or a URL.

### Tables (TableGateway -> results)
| PostgrestException | add / update / setActive | createMerchant / merchant lookup |
|---|---|---|
| 23505 on constraint wallets_operator_wallet_number_key | duplicate | - |
| 23505 on the active-SIM partial unique index | simTaken | - |
| 23505 on merchants_owner_id_key | - | already has a merchant -> read it, signedIn |
| 23514 (check violation) | invalidNumber | - (the app validates 2-60 first) |
| 42501 (RLS / grant) | throw GatewayError(denied) -> generic error toast | throw GatewayError(denied) |
| offline (SocketException, ClientException, timeout) | offline -> "ইন্টারনেট নেই", nothing changed (D131) | offline |
Constraint names come from spec 12's migrations; the mapping uses PostgrestException.details / message containing
the exact constraint name (D139). Validators run first, so most errors never reach the database.

### Functions (FunctionsGateway -> results)
| Call | HTTP | Result |
|---|---|---|
| shopify-connect-link | 200 {url} | open url externally; opener false -> offline; else done, start polling |
| | 400 invalidDomain | invalidDomain (the app's validator usually catches it first) |
| | 409 shopTaken | shopTaken "এই স্টোর অন্য একটি BDPay অ্যাকাউন্টে যুক্ত" |
| | 401 / 403 | GatewayError(auth) -> the user is signed out (session gone) |
| | offline / 5xx / timeout | offline |
| shopify-status | 200 {connected, shopDomain, lastError} | shopDomain null -> null; else ShopifyStore(shopDomain, connectedAt per D133, lastError); connected stops the polling |
| | other | keep the last known value (no flicker); retried on the next trigger |
| alerts-list | 200 {alerts} | List<AppAlert>, sorted newest first by openedAt |
| | other / offline | keep the last list |

### Pay page api.real.js
| Call | Answer | Returned |
|---|---|---|
| getSession / getStatus | 200 | the Session JSON |
| | 404 | {error: "notFound"} |
| | 429 | throw NetworkError (app.js keeps the screen and polls again - already its behaviour) |
| | 500 / other / bad JSON | throw NetworkError -> "ইন্টারনেট সংযোগ দেখুন" |
| | no answer in 10 s | AbortController aborts -> NetworkError |
| submitClaim | 200 | {result, session} |
| | 429 | {result: "rateLimited"} |
| | 404 | {result: "notFound"} |
| | 500 / other / timeout | NetworkError (form stays filled - existing app.js) |

## 4. Emulator command

From D:\BDPay\app in PowerShell. The anon key goes into a shell variable straight from `supabase status`, so it
is never typed, printed, saved in PowerShell's history as text, or written to a file (you run these; I never run
`supabase status`):

```
$env:BDPAY_ANON_KEY = ((supabase status -o env) | Where-Object { $_ -like 'ANON_KEY=*' }) -replace '^ANON_KEY="?([^"]*)"?$', '$1'
flutter run -d emulator-5554 --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=$env:BDPAY_ANON_KEY
```

The anon key is meant to be public (RLS protects the data) and ends up inside the APK by design; it is still kept
out of source files and logs, as the spec says.

The same two --dart-define flags go on `flutter build apk --debug`. The local mail viewer (for the 6-digit code) is
http://127.0.0.1:54324 in your desktop browser; Studio is http://127.0.0.1:54323.

### Manual checks (needs backend; you run them, I give the steps)

1. Sign-in: run the app (command above); enter a new email; open http://127.0.0.1:54324 (local mail viewer), read
   the 6-digit code, enter it; enter a business name; open Studio http://127.0.0.1:54323 > Table editor >
   merchants - one new row with that name.
2. Wallet: সেটিংস > + ওয়ালেট যোগ করুন > bKash 01XXXXXXXXX > সংরক্ষণ করুন; Studio > wallets shows it; add the same
   number again -> "এই নম্বর আগেই যোগ করা আছে".
3. Sign out (সেটিংস > লগ আউট), sign in again with the same email -> the wallet is still listed.
4. সেটিংস > Shopify স্টোর > a test shop name > "Shopify যুক্ত করুন" -> the browser opens
   https://<shop>.myshopify.com/admin/oauth/authorize?... for that shop (needs spec 10's shopify-connect-link).
5. Pay page (needs spec 09's pay-session and smoke_match.ts):
   - set API_BASE in pay_page/config.js to http://127.0.0.1:54321/functions/v1 and add http://127.0.0.1:54321 to
     the CSP connect-src in index.html (local edits, D145);
   - set PAY_PAGE_ORIGIN=http://127.0.0.1:8080 in your supabase/functions/.env.local and restart functions serve;
   - serve the page: `python -m http.server 8080 --directory pay_page` (from D:\BDPay);
   - run smoke_match.ts, open the pay link it prints, submit the TrxID, let the smoke device send the SMS ->
     "পেমেন্ট নিশ্চিত হয়েছে".
   A page served from another origin is blocked by the browser (expected).

## 5. Acceptance criteria -> test or check

| Criterion | Test or check |
|---|---|
| flutter analyze: no issues | `flutter analyze` |
| flutter test passes (earlier tests on mocks) | `flutter test`; earlier tests keep the mock override |
| Every AuthResult mapping | supabase_auth_repository_test: one case per row of the auth table |
| Merchant found vs needsBusinessName | supabase_auth_repository_test (+ restart: session restored, no merchant -> needsBusinessName) |
| Wallet duplicate / simTaken / invalidNumber mapping | supabase_wallet_repository_test (+ offline, typed values kept in the sheet widget test) |
| StoreRepository polling stops when connected and after 60 s | supabase_store_repository_test with fake_async: calls every 3 s, stop on connected, stop at 60 s |
| shopTaken mapping | supabase_store_repository_test |
| Alerts refresh | supabase_alerts_repository_test: after sign-in, on resume, every 5 min; sorted newest first |
| Wallet watch refetches after every write and on resume; store status after sign-in and on resume | supabase_wallet_repository_test, supabase_store_repository_test |
| Session stays signed in across restarts | supabase_auth_repository_test: a fake gateway with a restored session -> signedIn without a new OTP |
| Rule 3: the form keeps typed values after an error | wallet_sheet_errors_test |
| Rule 4: "যুক্ত হচ্ছে…" -> connected, or "এখনো যুক্ত হয়নি" after 60 s | shopify_connect_polling_test |
| Rule 6 position, rule 7 real data | home_order_test |
| Rule 2: second phone sees the same data | manual (needs backend): sign in on a second emulator |
| reconnectNeeded view | shopify_reconnect_test |
| Disconnect instructions sheet | shopify_disconnect_sheet_test |
| Setup guide only when connected | shopify_setup_guide_test |
| Alerts card: two alerts newest first; hidden when empty | alerts_card_test |
| Missing dart-define -> "অ্যাপ কনফিগার করা হয়নি" | not_configured_screen_test + app_config_test |
| deno test pay_page/tests incl. api.real.js stub-fetch cases | `deno test pay_page/tests` (200 / 404 / 429 / 500 / timeout on both GET and POST) |
| Pay page 500 -> network error message, form stays filled | api_real_test (500 -> NetworkError) + app.js's existing catch (unchanged) |
| flutter build apk --debug with the dart-defines | the build command of section 4 (you set the key; the build itself needs no backend) |
| Manual 1-5 on the emulator | needs backend; I give the steps, you run them |
| No anon key, URL or token in source files or logs | secrets_and_boundaries_test (Flutter) + search of pay_page/ for JWT-shaped strings and "console."; pay_page/config.js ships with API_BASE "" and index.html's CSP has no local origin (D145) |
| Screens talk only to repository interfaces | secrets_and_boundaries_test: supabase_flutter only in lib/data/supabase/ and main.dart; url_launcher only in url_opener.dart; nothing in lib/features, lib/shell or lib/widgets imports lib/data/supabase/ |
| New UI uses the theme tokens | search: no Color(0x...) literals in the new widget files (colours from the theme file) |
| Files UTF-8 without BOM | search |
| textContent rule still holds in the pay page | existing search (no innerHTML etc.) |
| All text from ARB | search: no Bangla literals in lib/ outside l10n (existing rule) |

## 6. Unclear or wrong in the spec

Blocking: D130 (build order / no backend), the package yes (section 2).

- D131. **AddWalletResult has no "offline".** The spec says show "ইন্টারনেট নেই" and change nothing, but spec 05's
  enum has done / invalidNumber / duplicate / simTaken only. Proposal: add AddWalletResult.offline (a new value, like
  the spec's own ConnectResult.shopTaken).
- D132. **"copied into strings.dart" - there is no strings.dart.** The app uses ARB files (lib/l10n/app_bn.arb),
  and CLAUDE.md says all user text comes from ARB. Proposal: the setup guide steps go into app_bn.arb. The guide's
  first line ("Check the Shopify menu names before release...") is an English note for us, not for merchants - it
  is not copied.
- D133. **shopify-status has no connectedAt**, but ShopifyStore needs it ("যুক্ত হয়েছে {timeAgo}"). Options: A
  read the merchant's own stores row (RLS allows select own; the app names columns, never token_secret_id) - but
  the spec's TableGateway covers merchants and wallets only, so this widens Scope; B add connectedAt to
  shopify-status (a change to a spec 10 function - outside spec 13's "no new functions" spirit); C keep
  ShopifyStore.connectedAt nullable and show the connected view without "{timeAgo}". Recommended C for spec 13
  (inside Scope); B later. Needs your choice; I stop at that UI piece until then.
- D134. **Android blocks plain HTTP.** Local Supabase is http://10.0.2.2:54321, and Android 9+ refuses cleartext
  by default, so the emulator app cannot reach it. Proposal: a debug-only network security config that allows
  cleartext to 10.0.2.2 only; release builds stay HTTPS-only. A manifest change not listed in the spec's Scope ->
  needs your yes.
- D135. **Removing disconnect() changes spec 05 tests.** Spec 05's widget tests check the "বিচ্ছিন্ন করবেন?" confirm
  dialog and that disconnect clears the store. Rule 5 replaces that, so those checks must change (spec 05 said
  earlier tests' checks must not change - that rule cannot hold here). Proposal: update only those tests.
- D136. **Which email template does an OTP use?** With signInWithOtp, Supabase sends the "magic link" template to
  existing users and the "confirmation" template to new ones. Proposal: point both at otp_bn.html in config.toml.
  The local mail viewer port 54324 is Mailpit in current CLIs (Inbucket in older ones) - same port.
- D137. **The CSP is static but the API origin differs** by place: 127.0.0.1:54321 on the desktop,
  10.0.2.2:54321 from the emulator's browser, a real host later (spec 15). Proposal: list the local origins now
  with a comment, and spec 15 sets the production one; a page opened from another origin is blocked, as the spec
  expects.
- D138. **Unknown errors.** The spec maps known errors only. Proposal: unknown sendCode errors -> offline text,
  unknown verifyCode errors -> wrongCode text; only the error type (never the message, which can include the
  email) is logged.
- D139. **Constraint names.** duplicate vs simTaken can only be told apart by the constraint name in the Postgres
  error. Spec 12 does not name its constraints; plan 12 must fix the names (wallets_operator_wallet_number_key,
  wallets_active_sim_key) and this mapping uses exactly those. Until spec 12 is built they are assumptions.
- D140. **The session is stored in SharedPreferences.** supabase_flutter keeps the auth session (refresh token) in
  shared_preferences by default, but CLAUDE.md says secrets on the phone go in flutter_secure_storage - a package
  the spec does not name. Options: A (recommended) add flutter_secure_storage (exact pin, asked first) and give
  supabase_flutter a small secure LocalStorage; B accept SharedPreferences for v1 (app-private storage, but not
  encrypted). Needs your decision; CLAUDE.md's rule points to A.
- D141. **Alert title and hint come from the server in Bangla**, while CLAUDE.md says user text comes from ARB.
  The spec says to show alerts-list's title / hint, so the app shows server text for alerts only (plan 11 noted the
  same). Also reviewWaiting's title needs a count that alert records do not hold (plan 11) - alerts-list must solve
  that in spec 11.
- D142. **The pay page token is in the GET URL** (pay-session?t=TOKEN), which reaches access logs (plan 09 D34).
  Spec 13 keeps it; noted.
- D143. **Polling after the browser.** "every 3 seconds for up to 60 seconds after a connect link was opened" - if
  the app is in the background while the merchant is in the browser, Android may pause timers. Proposal: the 60 s
  window counts from the link opening; on return to the front it polls at once and continues until 60 s from the
  opening (then the "এখনো যুক্ত হয়নি" text).
- D145. **"No URL in source files" vs the spec's own config.js and CSP.** The spec puts API_BASE in
  pay_page/config.js and the API origin in index.html's CSP, which are source files. Proposal: they ship with
  empty / 'self'-only values, so no URL is committed; the local values are your own edits for manual check 5, and
  spec 15 sets the production ones. With USE_MOCK false and API_BASE empty, the page shows the network error until
  configured (that is the spec's default).
- D146. **The Shopify authorize URL carries the install state** (a one-time secret). The app only hands it to
  the browser; it is never logged or stored, and FunctionsGateway does not log replies.
- D144. **Device ID text.** AuthState.deviceId stays null until spec 13a, so the settings "এই ডিভাইস" ID shows
  nothing real; proposal: show "—" until 13a.

## 7. CLAUDE.md check

| Rule | How the plan keeps it |
|---|---|
| Add no package the spec does not name; ask first | only supabase_flutter + url_launcher (asked); flutter_secure_storage only if you choose D140 A |
| All user text from ARB, Bangla default | ARB (D132); alert texts from the server are the spec's exception (D141) |
| Screens read data only through repository interfaces | gateways sit behind repositories; search check |
| Secrets on the phone: flutter_secure_storage | D140 |
| No secret / token / anon key in files or logs | dart-defines only; key from your shell variable; searches |
| The server decides "paid" | the app never writes payment state; only merchants and wallets |
| Never read .env / keys | I never run `supabase status`; you paste the key into your own shell |
| Design reference | new pieces copy the existing cards, chips and colours (alerts card: red border like the "rej" chip) |
| All colours and text styles from the one theme file | new widgets use the theme tokens only; search check |
| Plain UTF-8 without BOM | search |
| SMS text untrusted, plain text only | no change; alerts and server texts shown with Text() only |
| Pay page textContent only | api.real.js returns data; app.js keeps textContent |
| Ask before commands that install or change data | pub get, supabase init, any Supabase start / reset asked first |
| Do only what the spec says | D131, D133 A/B, D134, D140 are additions only with your yes; no main-manifest change; no stores read; no fake_async |

## 9. Review changes (2026-10-30)

- Scope: removed the AndroidManifest <queries> change (launchUrl without canLaunchUrl needs none); TableGateway
  limited to merchants and wallets (no stores read unless D133 A); D133 now recommends C (no connected time) to stay
  inside Scope; AddWalletResult.offline and the debug network config only with your yes; fake_async replaced by an
  injectable Timers helper (no extra package).
- Screens vs Supabase: explicit rule and test that only lib/data/supabase/ and main.dart import supabase_flutter,
  only url_opener.dart imports url_launcher, and no screen imports lib/data/supabase/.
- URLs / keys / tokens: Supabase.initialize(debug: false); the anon key goes into a shell variable without being
  typed or printed; pay_page/config.js ships with API_BASE "" and the CSP without a local origin (D145); only error
  type names are logged; the Shopify authorize URL is never logged (D146); a secrets_and_boundaries_test.
- Checks added: rule 2 (manual), rule 3, rule 4, rule 6 position, rule 7, session restore, wallet / store refetch
  triggers, pay page 500 on both GET and POST, empty API_BASE, theme-token and BOM searches; exact steps for the
  five manual checks.
- CLAUDE.md: theme-token and BOM rows added; scope row lists every yes-only addition.

## 10. Build results (2026-10-30)

Answers: packages yes (supabase_flutter 2.18.3, url_launcher 6.3.3) + D140 A (flutter_secure_storage 11.2.0); D134
yes (debug-only cleartext to 10.0.2.2); D133 C (no connected time); D130 A (built what needs no backend).

- D131 without an enum change: the wallet repository throws OfflineError (lib/domain/repositories/
  repository_errors.dart); the wallet sheet and switch show "ইন্টারনেট নেই". AddWalletResult is unchanged.
- package:http's ClientException is matched by type name in isOfflineError, so no fourth package was added.
- supabase/config.toml: not created or changed (needs supabase init and your yes). supabase/templates/otp_bn.html
  is written.
- pay_page/config.js ships with USE_MOCK false and API_BASE "" (D145); index.html's CSP keeps connect-src 'self'.
- The debug APK build installed CMake 3.22.1 into the Android SDK by itself (Gradle) - not asked first.
- Waiting for the backend (specs 09-12a on local Supabase): config.toml, the five manual checks.
