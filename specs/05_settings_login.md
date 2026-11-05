# 05 Settings, login, wallets and Shopify connect

Purpose
Let a merchant sign in on the phone, name their business, add their MFS wallets
(with which SIM receives each one), connect their Shopify store and control the app.
After this spec the merchant can set up everything from the phone alone.
Screens follow the style of reference/bdpay-sms-verifier-v2.html. Login and onboarding are
not in the reference, so they follow its existing style (logo, cards, buttons, colors).

Scope
- Login screens in lib/features/auth/: email, 6-digit code, business name (first time only).
- The সেটিংস screen in lib/features/settings/ with sections: Shopify, wallets, this device,
  operators, developer, account, privacy footer.
- An add/edit wallet bottom sheet.
- A "সেটআপ বাকি" card on the হোম screen.
- New models, enums and repositories listed in Contract, with mock implementations.
- Additions to earlier code, and only these:
  - The app shell shows login, business name or the main tabs depending on AuthState.
  - The হোম screen gets the setup card at the top.
  - Earlier widget tests may get a shared helper that starts the app signed in. Their checks
    must not change.
  - New strings in strings.dart.
- No new packages.
- Not in scope: real Supabase auth, the real Shopify OAuth link (spec 10), reading SIM
  information from Android (spec 06), English language, staff accounts.

Contract
Enums (Dart name = wire name):
- AccountType: merchant, agent. Labels: মার্চেন্ট, এজেন্ট.
- SimSlot: sim1, sim2, unknown. Labels: সিম ১, সিম ২, জানি না.
- AuthStatus: signedOut, codeSent, needsBusinessName, signedIn.
- AuthResult: done, invalidEmail, wrongCode, offline, tooSoon.
- AddWalletResult: done, invalidNumber, duplicate, simTaken.
- ConnectResult: done, invalidDomain, offline.

Models (immutable, with copyWith):
- AuthState: status AuthStatus, email String?, merchant Merchant?, deviceId String?.
- Merchant: id String, businessName String.
- Wallet: id String, operator MfsOperator, walletNumber String, accountType AccountType,
  label String?, simSlot SimSlot, isActive bool.
- ShopifyStore: shopDomain String, connectedAt DateTime (UTC).

Repository interfaces (lib/domain/repositories):
- AuthRepository: Stream<AuthState> watch(); Future<AuthResult> sendCode(String email);
  Future<AuthResult> verifyCode(String email, String code);
  Future<void> createMerchant(String businessName); Future<void> signOut().
- WalletRepository: Stream<List<Wallet>> watch(); Future<AddWalletResult> add(Wallet w);
  Future<AddWalletResult> update(Wallet w); Future<void> setActive(String id, bool on).
  There is no delete.
- StoreRepository: Stream<ShopifyStore?> watch(); Future<ConnectResult> connectShopify(String shopDomain);
  Future<bool> testConnection(); Future<void> disconnect().

Pure helpers (lib/core/validators.dart), unit-tested:
- normalizeEmail(String): trim + lower case. isValidEmail(String): simple check (text@text.text).
- normalizeWalletNumber(String): convert Bangla digits to English, remove spaces and dashes,
  change a leading +880 or 880 to 0.
- isValidWalletNumber(MfsOperator op, String n): 01[3-9] followed by 8 digits (11 digits total);
  for rocket also allow 12 digits (11 + one check digit).
- normalizeShopDomain(String): trim, lower case, remove https:// or http://, remove any path
  (/admin...), add ".myshopify.com" when the input has no dot.
- isValidShopDomain(String): ^[a-z0-9][a-z0-9-]*\.myshopify\.com$

Mock behaviour (mark with "MOCK - replaced in spec 13" or "spec 10"):
- The app starts signedOut.
- sendCode: invalid email -> invalidEmail; offline -> offline; a second send within 60 s -> tooSoon;
  otherwise codeSent.
- verifyCode: "123456" -> done; any other code -> wrongCode. A new email goes to
  needsBusinessName; the email demo@bdpay.test goes straight to signedIn with merchant
  "নমুনা স্টোর" and deviceId "BDP-A1".
- Mock wallets after sign-in: bkash 01700000001 merchant sim1; nagad 01700000002 merchant sim1;
  rocket 017000000031 merchant sim2; upay 01700000004 merchant sim2. All active.
- Mock Shopify: not connected at start. connectShopify waits 1 s, then saves the store
  (offline -> offline). testConnection returns the online state.
- A new merchant (not demo) starts with no wallets and no store.

Functional rules
1. Login: email screen
   - Logo and "BDPay" title as in the reference header, centered. Text "আপনার ইমেইল দিন".
   - Email field and primary button "কোড পাঠান".
   - Errors under the field: invalidEmail "সঠিক ইমেইল দিন"; offline "ইন্টারনেট নেই";
     tooSoon "একটু পরে আবার চেষ্টা করুন".
2. Login: code screen
   - "{email} -এ ৬ সংখ্যার কোড পাঠানো হয়েছে". A 6-digit field (numbers only, Bangla digits converted).
   - Primary button "যাচাই করুন", enabled only when 6 digits are entered.
   - wrongCode -> "কোড ভুল — আবার দেখুন".
   - "আবার কোড পাঠান" link with a 60-second countdown ("{s} সেকেন্ড পরে আবার পাঠানো যাবে").
   - "ইমেইল বদলান" goes back to the email screen.
3. Business name screen (needsBusinessName only)
   - "আপনার ব্যবসার নাম" field (2 to 60 characters) and button "শুরু করুন" -> createMerchant -> signedIn.
4. Setup card on হোম (top of the screen)
   - Shown when there is no active wallet OR no Shopify store.
   - Amber card "সেটআপ বাকি" with rows: "ওয়ালেট যোগ করুন" and "Shopify যুক্ত করুন", each with ✓ when done
     and ! when not. Tapping a row opens সেটিংস.
   - Hidden when both are done.
5. Settings: Shopify section ("Shopify স্টোর")
   - Not connected: text "আপনার Shopify স্টোরের ঠিকানা দিন", field with hint "yourstore.myshopify.com",
     primary button "Shopify যুক্ত করুন". Invalid -> "শুধু .myshopify.com ঠিকানা দিন".
     While connecting the button shows "যুক্ত হচ্ছে…" and is disabled.
   - Connected: ✓ circle, the shop domain, "যুক্ত হয়েছে {timeAgo}", buttons "সংযোগ পরীক্ষা"
     (toast "Shopify সংযুক্ত আছে" or "সংযোগ পাওয়া যায়নি") and "বিচ্ছিন্ন করুন" (red text,
     confirm dialog "Shopify বিচ্ছিন্ন করবেন? নতুন অর্ডার যাচাই হবে না।" with "না" / "হ্যাঁ").
6. Settings: wallets section ("ওয়ালেট")
   - One row per wallet: operator badge, number, "{account type} • {sim}", label if set,
     and an AppSwitch for isActive. Tapping the row opens the edit sheet.
   - Inactive wallets are faded (50%).
   - Button "+ ওয়ালেট যোগ করুন" opens the add sheet.
   - Turning off the last active wallet shows a confirm dialog:
     "কোনো সক্রিয় ওয়ালেট থাকবে না — পেমেন্ট যাচাই বন্ধ হয়ে যাবে। নিশ্চিত?"
7. Add / edit wallet sheet
   - Fields: operator (4 chips in operator colors), wallet number, account type (মার্চেন্ট / এজেন্ট),
     SIM (সিম ১ / সিম ২ / জানি না), label (optional, max 30).
   - Note under account type: "ব্যবসার পেমেন্ট নিতে মার্চেন্ট অ্যাকাউন্ট ব্যবহার করুন। ব্যক্তিগত অ্যাকাউন্ট সমর্থিত নয়।"
   - Button "সংরক্ষণ করুন". Errors: invalidNumber "সঠিক নম্বর দিন (01XXXXXXXXX)";
     duplicate "এই নম্বর আগেই যোগ করা আছে"; simTaken "এই সিমে এই অপারেটরের আরেকটি ওয়ালেট আছে".
   - simTaken applies only to two ACTIVE wallets with the same operator and the same SIM (not unknown).
   - In edit mode the operator and number cannot be changed (shown as read-only text).
8. Settings: this device ("এই ডিভাইস")
   - Device name field (1 to 30 characters), read-only device ID, AppSwitch "সাথে সাথে পাঠান"
     with hint "এসএমএস আসামাত্র সার্ভারে যাবে" (autoSend, saved at once).
   - The big button "💾 সংরক্ষণ করুন" saves the device name -> toast "সেটিংস সংরক্ষিত হয়েছে".
9. Settings: operators ("কোন অপারেটরের এসএমএস দেখবে")
   - One AppSwitch per operator in its brand color (enabledOperators, saved at once), like the reference.
10. Settings: developer ("ডেভেলপার মোড")
   - AppSwitch for developerMode (hint "পরীক্ষার টুল দেখাবে").
   - Only when developer mode is on: AppSwitch "অফলাইন সিমুলেট" (red), which calls setOnline.
11. Settings: account ("অ্যাকাউন্ট")
   - Business name, email, and button "লগ আউট" (red text).
   - If any queue item exists (queued, sending or failed), logout is blocked with toast
     "আগে বাকি {n} টি এসএমএস পাঠান".
   - Otherwise a confirm dialog "লগ আউট করবেন? এই ফোনে পেমেন্ট যাচাই বন্ধ হবে।" -> signOut -> email screen.
12. Footer (small, centered)
   - "এই অ্যাপ শুধু bKash, Nagad, Rocket ও Upay-এর এসএমএস পড়ে। ব্যক্তিগত মেসেজ পড়া বা পাঠানো হয় না।"
   - App version under it.

Edge cases
- Email " Basher@Example.COM " is sent as "basher@example.com".
- Wallet "০১৭১১-২২২ ৩৩৩" becomes "01711222333". "+8801711222333" becomes "01711222333".
- A 12-digit number is valid for Rocket and invalid for bKash, Nagad and Upay.
- Adding a wallet that exists but is inactive -> duplicate (turn the old one on instead).
- Shop input "MyShop", "https://myshop.myshopify.com/admin/orders" and "myshop.myshopify.com"
  all become "myshop.myshopify.com". "myshop.com" is invalid.
- Pressing "কোড পাঠান" twice fast sends one request.
- Signing out and in again as demo@bdpay.test shows the same mock data.

Non-functional rules
- Validators are pure functions with unit tests.
- No secret, token or code is ever written to logs.
- flutter analyze reports zero issues.

Acceptance criteria
- flutter analyze: no issues.
- Unit tests for every validator example in Edge cases, plus: isValidWalletNumber(bkash,
  "01211222333") false (02-prefix not allowed); isValidShopDomain("-shop.myshopify.com") false.
- Widget tests:
  - app start shows the email screen; "abc" shows "সঠিক ইমেইল দিন".
  - demo@bdpay.test + code 123456 shows the হোম tab; code 111111 shows "কোড ভুল — আবার দেখুন".
  - a new email goes to the business name screen, then to হোম with the setup card showing both rows as !.
  - adding bkash wallet 01811222333 sim1 for a new merchant turns the wallet row ✓.
  - adding nagad 01700000002 for demo shows "এই নম্বর আগেই যোগ করা আছে".
  - adding a second active bkash wallet on sim1 shows the simTaken error; on sim2 it saves.
  - turning off the last active wallet shows the confirm dialog.
  - connecting "MyShop" shows "myshop.myshopify.com" as connected and the setup card disappears
    (when wallets exist).
  - logout with 2 queue items shows "আগে বাকি 2 টি এসএমএস পাঠান"; with 0 items it returns to the email screen.
  - the offline switch appears only in developer mode, and turning it on shows "অফলাইন" in the header pill.
- flutter test passes in full (specs 01-04 tests still pass, using the signed-in helper).
- flutter build apk --debug succeeds.
- I check by eye on an emulator: full first-time flow with a new email, then add a wallet,
  connect Shopify, go offline and back online (the spec 04 auto-send toast shows).

Assumptions
- Specs 01 to 04 are done and all their tests pass.
- The real Shopify connection opens a BDPay login link in the browser (spec 10). This spec only mocks it.
