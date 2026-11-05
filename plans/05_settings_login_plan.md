# Plan 05 - Settings, login, wallets and Shopify connect

Spec: specs/05_settings_login.md (builds on specs 01-04)
Status found: code for specs 01-04 is in app/ (not re-run for this plan; step 0 runs analyze + test first).

Decisions carried over
- D1 = A: where the spec says "strings.dart", this plan uses app/lib/l10n/app_bn.arb.
- The design reference is the root file "BDPay SMS Verifier.html" (reference/bdpay-sms-verifier-v2.html does not exist).

Decisions taken (2026-10-29): D6 = allow, D7 = A, D8 = A, D9 = A.

Decisions needed before execution
- D6. **The settings tab must show SettingsScreen, and the spec doesn't list that shell change.** Allowed is only "the app shell
  shows login, business name or the main tabs depending on AuthState". Same pattern as D2/D3/D5: one extra change, the
  সেটিংস tab shows SettingsScreen instead of the placeholder. Approve, or change the spec.
- D7. **setActive() cannot report a conflict.** `Future<void> setActive(String id, bool on)` gives no result, but turning on an
  inactive bKash wallet on sim1 while another active bKash wallet is on sim1 breaks the simTaken rule (rule 7). The edge
  case "duplicate -> turn the old one on instead" sends users straight into this. Options:
  A (recommended) change the contract to `Future<AddWalletResult> setActive(...)` (done or simTaken) and show the simTaken
  text as a toast; B keep void, the mock silently refuses and the UI pre-checks with the pure rule function.
- D8. **App version in the footer without a new package.** package_info_plus is not allowed. Options:
  A (recommended) a const `appVersion = '1.0.0+1'` in lib/core/app_info.dart, plus a unit test that reads pubspec.yaml and
  fails if they differ; B pass it with `--dart-define=APP_VERSION=...` (empty in tests and in plain `flutter run`).
- D9. **What "duplicate" means.** The same phone number can legally have both a bKash and a Nagad account. Options:
  A (recommended) duplicate = same operator + same number (bKash 01711222333 and Nagad 01711222333 can both exist);
  B duplicate = same number for any operator. Both pass the spec's test (nagad 01700000002).

## 1. Files

### New files
Domain (app/lib/domain/)
- account_enums.dart - AccountType, SimSlot (toWire/fromWire + Bangla label(l)), AuthStatus, AuthResult, AddWalletResult,
  ConnectResult. A new file, like spec 03's review.dart, so enums.dart is not touched.
- models/auth_state.dart - AuthState(status, email?, merchant?, deviceId?) with copyWith.
- models/merchant.dart - Merchant(id, businessName) with copyWith.
- models/wallet.dart - Wallet(id, operator, walletNumber, accountType, label?, simSlot, isActive) with copyWith.
- models/shopify_store.dart - ShopifyStore(shopDomain, connectedAt UTC) with copyWith.
- repositories/auth_repository.dart - the AuthRepository interface from Contract.
- repositories/wallet_repository.dart - the WalletRepository interface (no delete).
- repositories/store_repository.dart - the StoreRepository interface.
- wallet_rules.dart - pure `checkWallet(existing, candidate, {editingId})` -> done / invalidNumber / duplicate / simTaken
  (simTaken only for two ACTIVE wallets, same operator, same SIM, SIM not unknown). Used by the mock now, mirrored by
  the server later.

Helpers (app/lib/core/)
- validators.dart - normalizeEmail, isValidEmail, normalizeWalletNumber, isValidWalletNumber, normalizeShopDomain,
  isValidShopDomain, plus a shared Bangla->English digit converter (also used by the 6-digit code field) and length checks
  for business name (2-60), device name (1-30) and wallet label (max 30), so widgets hold no rules.
- app_info.dart - appVersion const (D8 = A).

Mock data (app/lib/data/)
- mock/mock_account_data.dart - the demo merchant ("নমুনা স্টোর", deviceId "BDP-A1"), the 4 demo wallets, and an in-memory
  map email -> merchant/wallets/store so signing out and in keeps the same data. Marked "MOCK - replaced in spec 13".
- mock/mock_auth_repository.dart - MockAuthRepository: starts signedOut; sendCode (invalidEmail / offline from
  DeviceHealth / tooSoon within 60 s per email / codeSent); verifyCode ("123456" only; demo -> signedIn, new email ->
  needsBusinessName); createMerchant; signOut. Optional initial state for tests. Time comes from clockProvider (UTC),
  so tests can move it. Never logs the email or code. "MOCK - replaced in spec 13".
- mock/mock_wallet_repository.dart - MockWalletRepository: follows the signed-in merchant; empty when signed out;
  add/update normalise the number and use checkWallet; assigns ids; setActive. "MOCK - replaced in spec 13".
- mock/mock_shopify_repository.dart - MockShopifyRepository (not "mock_store", that name is taken by MockStore):
  connectShopify waits 1 s, normalises + validates, offline -> offline, connectedAt = clockProvider time (UTC);
  testConnection = online state; disconnect. "MOCK - replaced in spec 10".
- account_providers.dart - authRepositoryProvider, walletRepositoryProvider, storeRepositoryProvider and the stream
  providers authStateProvider, walletsProvider, shopifyStoreProvider. A new file, so providers.dart is not touched.

Login screens (app/lib/features/auth/)
- email_screen.dart - logo + "BDPay" centered, "আপনার ইমেইল দিন", email field, "কোড পাঠান" (busy guard: one request per
  tap burst), errors under the field.
- code_screen.dart - "{email} -এ ৬ সংখ্যার কোড পাঠানো হয়েছে", 6-digit field (digits only, Bangla converted),
  "যাচাই করুন" enabled at 6 digits, wrongCode text, resend link with 60 s countdown, "ইমেইল বদলান".
- business_name_screen.dart - "আপনার ব্যবসার নাম" (2-60), "শুরু করুন" -> createMerchant.
- widgets/auth_layout.dart - shared centered layout (logo, title, card) in the reference style. The "BDPay" title
  uses the existing headerBrand ARB string.
- widgets/auth_logo.dart - the emerald shield logo, colours from colors.dart. The header draws it inline; extracting
  it would change app_header.dart, which the spec doesn't allow, so the small drawing is repeated here.
- widgets/resend_countdown.dart - the "আবার কোড পাঠান" link / "{s} সেকেন্ড পরে আবার পাঠানো যাবে" text.

Settings screen (app/lib/features/settings/)
- settings_screen.dart - the tab: sections in spec order in one scrolling list, footer last.
- settings_rules.dart - pure helpers: isLastActiveWallet(wallets, id), logoutBlockedCount(transactions) (uses spec 04
  queueItems: queued + sending + failed).
- widgets/settings_section.dart - section card with a title (reference "card s big" style).
- widgets/shopify_section.dart - not connected (field, hint, button, "যুক্ত হচ্ছে…") / connected (✓, domain,
  "যুক্ত হয়েছে {timeAgo}", "সংযোগ পরীক্ষা", red "বিচ্ছিন্ন করুন" + confirm).
- widgets/wallets_section.dart - wallet rows, "+ ওয়ালেট যোগ করুন", last-active confirm.
- widgets/wallet_row.dart - operator badge, number, "{account type} • {sim}", label, AppSwitch, 50% when inactive.
- widgets/wallet_sheet.dart - add/edit bottom sheet + showWalletSheet(); operator chips in brand colours, number,
  account type + note, SIM, label; read-only operator/number in edit mode; error texts.
- widgets/device_section.dart - device name field, read-only device ID (from AuthState.deviceId), "সাথে সাথে পাঠান" switch,
  "💾 সংরক্ষণ করুন" button + toast.
- widgets/operators_section.dart - one AppSwitch per operator in its brand colour.
- widgets/developer_section.dart - developer-mode switch; red "অফলাইন সিমুলেট" switch only in developer mode (setOnline).
- widgets/account_section.dart - business name, email, red "লগ আউট" (blocked toast or confirm -> signOut).
- widgets/privacy_footer.dart - the privacy sentence and the app version.
- widgets/confirm_dialog.dart - showConfirmDialog(text, no, yes) used for disconnect, last wallet and logout.

Home
- app/lib/features/home/setup_status.dart - pure: SetupStatus(hasActiveWallet, hasStore, show).
- app/lib/features/home/widgets/setup_card.dart - amber "সেটআপ বাকি" card, two rows with ✓ / !, tap -> সেটিংস tab.
(No new files in the shared lib/widgets folder: the logo and the dialog stay inside the features that use them.)

Tests (app/test/)
- core/validators_test.dart - every Edge-case example + the 2 extra cases + length checks.
- core/app_info_test.dart - appVersion equals the pubspec version (D8 = A).
- domain/account_enums_test.dart - toWire/fromWire round trip, unknown throws.
- domain/wallet_rules_test.dart - duplicate (also inactive), simTaken only for active + same op + same SIM, unknown SIM
  never taken, editing a wallet doesn't clash with itself.
- data/mock_auth_repository_test.dart - all sendCode/verifyCode results, tooSoon at 59 s / ok at 61 s (fake clock),
  demo vs new email, sign out + in keeps data.
- data/mock_wallet_repository_test.dart - demo wallets, new merchant empty, normalised number stored, results.
- data/mock_shopify_repository_test.dart - 1 s wait, offline, invalid, testConnection, disconnect.
- features/settings/settings_rules_test.dart - isLastActiveWallet, logoutBlockedCount.
- features/home/setup_status_test.dart - the 4 combinations.
- signed_in_overrides.dart - THE shared helper the spec allows: signedInOverrides() returns provider overrides with the
  demo merchant signed in, its 4 wallets and a connected store (so the setup card is hidden).
- account_test_helpers.dart - pumpSignedOut / pumpSignedIn(demo or new merchant, store connected or not) on the full
  app with a fixed clock, for the new spec 05 tests.
- features/auth/login_flow_test.dart - login widget tests.
- features/settings/settings_screen_test.dart - wallet, Shopify, logout, device, operators, developer widget tests.
- features/home/setup_card_test.dart - setup card rows and hiding.

### Changed earlier files
- [CHANGED 01/04] app/lib/shell/app_shell.dart:
  - body chooses by AuthState: signedOut/codeSent -> email or code screen; needsBusinessName -> business name screen;
    signedIn -> header + tabs + bottom nav. (Allowed: "The app shell shows login, business name or the main tabs")
  - the সেটিংস tab shows SettingsScreen. (Needs D6)
  - the sync coordinator still starts once in initState, unchanged.
  - nothing else (no tab reset on sign-in; see section 4, item 16).
- [CHANGED 02] app/lib/features/home/home_screen.dart - SetupCard as the first item of the list. (Allowed)
- [CHANGED 01] app/lib/l10n/app_bn.arb - all new strings. (Allowed: "New strings")
- [CHANGED 01, generated] app/lib/l10n/app_localizations.dart and app_localizations_bn.dart - regenerated from the ARB
  by the build, never edited by hand.
- [SPEC CHANGE, only if D7 = A] the new wallet_repository.dart setActive returns AddWalletResult instead of void.
  This changes the spec's Contract, so it happens only with your yes.
- [CHANGED tests] each earlier helper only adds `...signedInOverrides()` to its existing override list; no test body and
  no expect() changes (Allowed: "Earlier widget tests may get a shared helper that starts the app signed in"):
  - app/test/test_helpers.dart - pumpApp.
  - app/test/features/transactions/transactions_test_helpers.dart - pumpAppAt (queue tests use it too).
  - app/test/features/home/home_test_helpers.dart - pumpHome.
  Checked earlier assertions that could be hit: home "অফলাইন" findsOneWidget, "5 TransactionCards", queue
  "ইন্টারনেট নেই" findsOneWidget, the stale text findsNWidgets(2), the 4/5 tab order. The setup card is hidden by the
  helper, the settings screen is never on screen in those tests (the shell builds only the selected tab), and no new
  text repeats those strings on the same screen, so none of them change.

### Not changed (on purpose)
- providers.dart, enums.dart, every spec 01-04 repository, mock and model, app.dart, app_header.dart, spec 02-04 widgets.
- Every earlier test file other than the three helpers above; no expect() changes.
- pubspec.yaml: no new packages.

## 2. Order of work

0. flutter analyze + flutter test: confirm specs 01-04 are green. Get your answers on D6-D9.
1. validators.dart + validators_test.dart (+ app_info.dart and its test). analyze; test.
2. account_enums.dart, the 4 models, the 3 interfaces, wallet_rules.dart + tests. analyze; test.
3. Mock data, the 3 mock repositories, account_providers.dart + mock tests. analyze; test.
4. New strings in app_bn.arb (flutter gen-l10n via build). analyze.
5. signed_in_overrides.dart, then add it to the 3 earlier test helpers (before the shell changes, so the earlier tests
   never run against a signed-out app).
6. Login screens (with auth_logo.dart), then the shell AuthState switch. analyze. Full flutter test: specs 01-04 must be
   green again before going on.
7. account_test_helpers.dart.
8. login_flow_test.dart. test.
9. setup_status.dart + setup card + home_screen.dart change + setup_card_test.dart. test.
10. Settings: rules + tests, then sections one by one (Shopify, wallets + sheet, device, operators, developer, account,
    footer), then the shell's settings tab (D6). settings_screen_test.dart. analyze; test.
11. Full flutter analyze, full flutter test, flutter build apk --debug, the searches in section 3.
12. You check by eye on the emulator (also the spec 04 offline -> online check, now possible with the offline switch).

## 3. Acceptance criteria -> check

| Criterion | Check |
|---|---|
| flutter analyze: no issues | "No issues found!" |
| Email " Basher@Example.COM " -> "basher@example.com" | validators_test |
| "০১৭১১-২২২ ৩৩৩" -> "01711222333"; "+8801711222333" -> "01711222333" | validators_test |
| 12 digits valid for Rocket, invalid for bKash/Nagad/Upay | validators_test (all 4 operators) |
| isValidWalletNumber(bkash, "01211222333") false | validators_test |
| "MyShop", "https://myshop.myshopify.com/admin/orders", "myshop.myshopify.com" -> "myshop.myshopify.com"; "myshop.com" invalid | validators_test |
| isValidShopDomain("-shop.myshopify.com") false | validators_test |
| Inactive existing wallet -> duplicate | wallet_rules_test + mock_wallet_repository_test |
| "কোড পাঠান" twice fast -> one request | login_flow_test with a counting fake AuthRepository: two taps, count = 1 |
| Sign out and in as demo shows the same data | mock_auth_repository_test + a login_flow_test round trip |
| App start shows the email screen; "abc" -> "সঠিক ইমেইল দিন" | login_flow_test |
| demo@bdpay.test + 123456 -> হোম tab | login_flow_test: nav-home active, header visible |
| code 111111 -> "কোড ভুল — আবার দেখুন" | login_flow_test |
| New email -> business name screen -> হোম with setup card, both rows ! | login_flow_test |
| New merchant adds bkash 01811222333 sim1 -> wallet row ✓ | setup_card_test (full app: settings -> sheet -> back to হোম) |
| Demo adds nagad 01700000002 -> "এই নম্বর আগেই যোগ করা আছে" | settings_screen_test |
| Second active bkash on sim1 -> simTaken text; on sim2 -> saves | settings_screen_test (row count goes 4 -> 5) |
| Turning off the last active wallet -> confirm dialog | settings_screen_test (new merchant with 1 wallet; also demo after 3 off) |
| Connect "MyShop" -> "myshop.myshopify.com" connected, setup card gone (with wallets) | settings_screen_test + setup_card_test (pump past the 1 s wait) |
| Logout with 2 queue items -> "আগে বাকি 2 টি এসএমএস পাঠান" | settings_screen_test with sample data (2 queue items) |
| Logout with 0 items -> email screen | settings_screen_test: retryAllPending first, then logout + "হ্যাঁ" |
| Offline switch only in developer mode; on -> "অফলাইন" in the header pill | settings_screen_test |
| flutter test passes in full (01-04 with the signed-in helper) | full `flutter test`; diff of earlier test files shows only helper changes |
| flutter build apk --debug succeeds | exits 0, app-debug.apk exists |
| No secret, token or code written to logs | search: no print/debugPrint/log( in lib/ |
| Validators are pure and unit-tested | review: validators.dart imports nothing from Flutter |
| No new packages | pubspec.yaml unchanged |
| By eye on the emulator: first-time flow, add wallet, connect Shopify, offline/online + auto-send toast | you |

Functional rules (not listed as criteria, checked too)

| Rule | Check |
|---|---|
| offline / tooSoon texts on the email screen | login_flow_test (setOnline(false); second send within 60 s) |
| "যাচাই করুন" disabled until 6 digits; Bangla digits accepted | login_flow_test: "১২৩৪৫৬" verifies |
| Resend countdown text and link after 60 s | login_flow_test (pump 60 s) |
| "ইমেইল বদলান" returns to the email screen | login_flow_test |
| Business name < 2 or > 60 chars blocked | validators_test + login_flow_test |
| Setup card rows open সেটিংস | setup_card_test |
| Shopify invalid input text; "যুক্ত হচ্ছে…" and disabled while connecting | settings_screen_test |
| "সংযোগ পরীক্ষা" toasts online / offline; disconnect confirm "না" keeps, "হ্যাঁ" removes | settings_screen_test |
| Inactive wallet row at 50%; edit sheet shows operator and number read-only | settings_screen_test |
| simTaken ignores SIM "জানি না" and inactive wallets | wallet_rules_test |
| Device name 1-30, save toast "সেটিংস সংরক্ষিত হয়েছে"; autoSend saved at once | settings_screen_test |
| Operator switches use each operator's brand colour; turning one off -> হোম tile shows "বন্ধ" | settings_screen_test (reads AppSwitch.activeColor) |
| "অফলাইন সিমুলেট" switch is red | settings_screen_test (activeColor = er) |
| Logout confirm "না" keeps the user signed in | settings_screen_test |
| Mock wallets / no store / starts signedOut, as listed in Mock behaviour | mock_*_repository_test |
| Footer text and version | settings_screen_test |
| Mock code marked "MOCK - replaced in spec 13" / "spec 10" | search |
| No Color( outside colors.dart, no double for money | searches (as in spec 01) |
| No hard-coded user text in the new screens | search: no Text('...') / string literals with Bangla or English words in lib/features/auth, settings, setup_card |
| Times in UTC (connectedAt, rate limit) | mock_shopify_repository_test: connectedAt.isUtc |
| New files UTF-8 without BOM | search: no file under app/lib or app/test starts with EF BB BF |
| SMS text never shown as markup | unchanged; no new SMS display |

## 4. Unclear or wrong in the spec

1. **Settings tab in the shell not listed.** -> D6.
2. **setActive gives no result.** -> D7.
3. **App version without a package.** -> D8.
4. **Duplicate rule.** -> D9.
5. **strings.dart / reference file name.** Same as before: ARB (D1), and the root "BDPay SMS Verifier.html".
6. **"ইমেইল বদলান" has no repository method.** The shell shows screens from AuthState, so going back must change the state.
   Plan: call signOut() (codeSent -> signedOut). The tooSoon limit is per email, so the user can send to a corrected
   email at once. Say if the limit should be for the device instead.
7. **deviceId for a new merchant is not given.** Only demo gets "BDP-A1". Plan: the mock gives new merchants "BDP-" + a
   short counter ("BDP-N1"). The real ID comes from pairing/backend later.
8. **Phone login vs "a device is not a user" (CLAUDE.md).** The spec signs the owner in on the phone. That is fine as a mock,
   but the real flow (spec 13) should turn the login into a device registration with its own device secret, not keep an
   owner session on the phone. Noted, nothing to do now.
9. **Where the sync coordinator runs.** It is started once in the shell at app start (spec 04) and keeps running while signed
   out. With the mock it only matters when queue items exist; logout is blocked while any exist, so nothing is sent
   for a signed-out user in practice.
10. **Transactions per merchant.** The spec gives new merchants no wallets and no store but says nothing about transactions,
    so the sample transactions still show for every merchant. Fine for a mock; per-merchant data comes with the backend.
11. **Offline Shopify error text missing.** connectShopify can return offline, but rule 5 has no text. Plan: reuse
    "ইন্টারনেট নেই" under the field.
12. **Confirm dialog buttons.** Only the Shopify dialog names its buttons. Plan: the last-wallet and logout dialogs use the
    same "না" / "হ্যাঁ".
13. **Unsaved device name.** Other device settings save at once, the name only with "💾 সংরক্ষণ করুন". Leaving the tab drops
    an unsaved name. Plan: keep it that way (as written).
14. **Offline switch when developer mode is turned off.** If the user turns developer mode off while "offline" is on, the app
    stays offline with no switch to undo it. The spec doesn't say what to do, so the plan does nothing extra (that would be
    outside Scope). If you want "developer mode off -> back online", add it to the spec.
15. **Earlier tests and the setup card.** The signed-in helper uses demo + a connected store, so the setup card is hidden and
    spec 01-04 checks see the same screens. Without the store, the card would push the হোম content down.
16. **Sign-in tab.** After logout from সেটিংস and a new sign-in, the app opens on সেটিংস again (the selected tab is kept). The
    spec's test only covers the first sign-in, which opens on হোম. Resetting the tab is not in Scope, so the plan doesn't
    do it. Add it to the spec if you want it.
17. **CLAUDE.md folder names and go_router.** CLAUDE.md names apps/mobile and go_router; the app lives in app/ and uses the
    Riverpod tab provider since spec 01. Unchanged here (no new packages allowed).

## 5. Review log

Review 1 against spec 05 and CLAUDE.md:
- Outside Scope: nothing found. No real Supabase, no OAuth, no SIM reading, no English, no staff accounts.
- Earlier files changed: app_shell.dart (allowed part + D6), home_screen.dart (allowed), app_bn.arb (allowed), three test
  helpers (allowed, no expect() changes). enums.dart and providers.dart stay untouched by using new files.
- Every acceptance criterion has a check; the emulator check stays manual.
- CLAUDE.md: wallet numbers are digit strings; account types only merchant/agent (no Personal/PRP from the reference);
  no device key field (the reference has one; the spec shows only a read-only device ID); no delete for wallets; nothing
  marked verified on the device; text in ARB; colours from the theme; no logging of codes.

Review 2 (scope, earlier files, criteria, CLAUDE.md):
- Outside Scope, removed: "developer mode off -> setOnline(true)" and "reset to হোম on every sign-in" were extra behaviour;
  both are now only questions (section 4, items 14 and 16). New shared widgets in lib/widgets (app_logo, confirm_dialog)
  moved into the auth and settings feature folders.
- Earlier files: the test-helper change is now one new shared helper (signed_in_overrides.dart) that the 3 earlier helpers
  only add to their override lists; the earlier assertions that could be affected were checked one by one. The generated
  l10n files are listed as changed. The D7 contract change is marked as a spec change that needs your yes.
- Criteria: all had a check. Added checks for rules that had none: operator switch colours, red offline switch, logout "না",
  the mock starting data, no hard-coded text, UTC times, no BOM.
- CLAUDE.md: mocks now take time from clockProvider and store connectedAt in UTC; the login "BDPay" title comes from ARB;
  logo colours from colors.dart. The go_router / apps/mobile mismatch (item 17) predates this spec and is not changed.

## 6. Execution log (2026-10-29)

- Done in plan order, except: all new ARB strings were added in step 2 (the enum labels need them).
- No fake_async (not a direct dependency, no new packages): the Shopify 1 s wait is tested with a real 1 s delay.
- Bug found by the "two fast taps" test: the mock answers before the second tap, so the email screen now stays busy after
  a successful send (the code screen replaces it).
- Seen in a test: going back online while signed out starts the spec 04 auto-send (section 4, item 9). Unchanged.
- Labels the spec does not give, added to ARB: sheet labels "ওয়ালেট নম্বর", "অ্যাকাউন্ট টাইপ", "সিম", "লেবেল (ঐচ্ছিক)", edit-sheet title
  "ওয়ালেট"; device "ডিভাইস নাম" / "ডিভাইস আইডি" (from the reference); account "ব্যবসার নাম" / "ইমেইল"; footer "ভার্সন {version}".
- Results: flutter analyze clean; flutter test 186 passed (102 before); flutter build apk --debug built.
