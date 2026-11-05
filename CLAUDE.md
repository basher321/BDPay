# BDPay project conventions

These rules apply to every file you write in this project.

Product
- BDPay verifies Bangladeshi MFS payments (bKash, Nagad, Rocket, Upay). The merchant's Android
  phone forwards MFS SMS to the server; the server matches each SMS to a customer's payment
  claim and marks the order paid.
- The server is the only thing that decides "paid". The app and dashboard only show the
  server's result. Never mark anything verified on the device.
- Many merchants use one installation. Every merchant-owned table has a NOT NULL merchant_id,
  and a merchant can only ever see its own rows.
- Product spec: docs/specs/001-product-spec.md. Step specs: specs/NN_name.md. When they differ,
  the current step spec wins. Do only what the current step spec says.

Design reference
- The design reference is "BDPay SMS Verifier.html" in the project root. Every Android app
  screen must look and behave like it: colours, spacing, cards, chips, bottom navigation,
  Bangla wording. Never redesign.
- If something is missing in the reference (web dashboard, pairing, customer page), follow its
  existing style and colour tokens.
- The reference is a mock. Do not copy its demo behaviour where it breaks these rules: local
  sync that marks verified, a typed device key, Personal/PRP account types, delete-all history,
  decimal amounts.

Folders
- apps/mobile              Flutter Android app (Android 8+)
- apps/dashboard           Flutter web: merchant dashboard and customer TrxID page
- packages/bdpay_shared    Dart models, enums, parser, money and date helpers used by both apps
- supabase/migrations      numbered SQL migrations
- supabase/functions       Edge Functions (TypeScript, Deno)
- supabase/tests           SQL and function tests
- specs/                   one spec per step; plans/ one plan per step
- shopify_app/    Shopify app config and checkout extension

Frontend rules
- Flutter stable with null safety. State: flutter_riverpod. Navigation: go_router.
  Phone local database: drift (SQLite). Secrets on the phone: flutter_secure_storage.
- SMS capture is a native Kotlin BroadcastReceiver that writes to the local queue even when
  the Flutter UI is not running. No third-party SMS plugin.
- Add no package that the current spec does not name.
- All colours and text styles come from one theme file that copies the reference tokens
  (--em #00D09C, --bg #080D1A, --sf #10192D, --cd #17233D, --bd #233558, operator colours).
- All user-facing text comes from l10n ARB files. Bangla (bn) is the default. No hard-coded text.
- Screens read data only through repository interfaces. Until the backend steps, a mock
  implementation is used; switching to the real one must not change any screen.
- SMS text is untrusted. Show it only as plain text, never as HTML or markup.

Money and data
- Money is a whole number of poisha (1 taka = 100 poisha): int in Dart, BIGINT in SQL,
  integer in TypeScript. Never use float or double for money. Money names end in _poisha.
  Show money as "৳ 1,250.00".
- Times are stored in UTC as ISO 8601 / timestamptz and shown in Asia/Dhaka.
- Wallet and phone numbers are digit strings, never numbers. TrxID is stored trimmed and uppercase.

Backend rules
- Each phone has its own ECDSA P-256 key pair in the Android Keystore. The server stores only the public key.
- Device requests are signed with that key over the function name, a timestamp and the body hash. Reject requests older than 5 minutes.
- Edge Function logic talks only to the Store interface in supabase/functions/_shared/store.ts. Never put SQL or Supabase calls in handlers.

Fixed values (use exactly these: Dart enums, TypeScript string unions, SQL CHECK lists)
- operator: bkash, nagad, rocket, upay
- wallet account_type: merchant, agent
- claim status: pending, verified, mismatch, expired, rejected, superseded (spec 09: replaced by a
  newer claim on the same session)
- claim mismatch_reason: amount, duplicate_trxid
- sms status: received, unmatched, matched, rejected
- device status: active, revoked
- device queue status: queued, sending, sent, failed
- UI mapping to the reference: verified = green "ok" chip, pending = amber "pe" chip,
  mismatch/expired/rejected = red "rej" chip; queue sent = Synced, queued/sending = Queue,
  failed = Failed.

Roles
- v1 has one dashboard role: owner, with full access to its own merchant only.
- BDPay admin work is done in Supabase Studio; there are no admin screens in v1.
- A device is not a user. It signs every request with its own device key (see Backend rules).

Security
- The server re-parses every raw SMS and never trusts the device's parsed values.
- Sender whitelist is checked on the device and on the server.
- Row-level security is enabled on every table with merchant_id.
- Payment claims, SMS records and matches are never deleted; corrections go to audit_log.

Files
- Plain ASCII or UTF-8 text with no byte-order mark.
- Do not add features, pages or packages outside the current spec's Scope.

Safety rules (never break these, even if asked in a prompt)
- Never delete, drop or truncate a database, schema or table. Never run DROP, TRUNCATE or
  DELETE without a WHERE clause. Never run supabase db reset. If a task seems to need this,
  stop and ask me.
- Never delete folders or many files at once. Never run rm -rf, rmdir /s or Remove-Item -Recurse.
- Never run git push --force, git reset --hard or git clean -f.
- Never read, print or change .env files, keystores, key.properties, passwords, API keys,
  Shopify tokens or device secrets. Logins and passwords are typed by the owner in their own
  terminal (for example `! supabase login`); Claude Code never uses a password pasted in chat.
  Exception: the project's PUBLISHABLE (anon) key is public by design (every APK carries it); it may be
  passed to `flutter build` / `flutter run` as --dart-define only, never written to a repo file. Secret and
  service-role keys stay forbidden.
- Remote Supabase (changed by the owner on 2026-10-30): only the BDPay project
  ilidxuukjybrtvrkgjrg. Linking to it, `supabase db push` (new migrations only) and
  `supabase functions deploy` / `supabase secrets set` for it are allowed. No other remote
  project. Every other safety rule here applies to it too (no reset, drop, truncate or delete).
- GitHub: only github.com/basher321/BDPay. Commits and normal pushes are allowed; never force push.
- Standing approval (2026-10-30): installing the Supabase CLI and the packages a spec names
  (pinned versions), and committing/pushing finished, tested specs. Anything else that changes
  data, files outside this project, or installed software: explain what it will do and wait
  for my yes.
- A database change is made only by adding a new numbered migration file. Never edit or
  delete an old migration.
