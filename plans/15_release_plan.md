# Plan 15 - Release

Spec: specs/15_release.md. Written 2026-10-30.
Read with: CLAUDE.md, specs 11, 13a, 14, 15, plans 13a/14 and the current code (mailer.ts, heartbeat.ts, http.ts,
fake_store.ts, HeartbeatRun.kt / DeviceConfig.kt / PipelineState.kt, Dart pipeline_state.dart, home and settings
screens, url_opener.dart, app/android/app/build.gradle.kts, pay_page/, the two existing .gitignore files).

Reviewed 2026-10-30 against the spec and CLAUDE.md; section 7 lists what the review changed.

Decisions and build notes (2026-10-30): D210 = A, health takes a RateLimiter (new _shared/rate_limit.ts with the
interface and a MemoryRateLimiter for tests / FakeStore mode; without a limiter health answers 503 and logs
"rateLimiterMissing"); D211 = the rules read; D214 = a separate staging keystore (staging runbook step 9 changed);
D219 = SITE_URL yes; D220 = no (no support contact in the app - release_checklist.txt says how to answer that
line); D232 = onboarding step (production runbook, after step 11); D215 = you declined the scratch-folder
check-ignore run, so that criterion is not run. Build notes: health's 405 says "Only GET is allowed."; when
depsFromEnv gives no store, serveFunction still answers its shared 503 storeNotReady body (not {ok:false,
db:false}) - a monitor sees 503 either way. Claude Code's sandbox also blocks an existence test on
key.properties; the release-failure check ran once while the file did not exist.

Default rule: until you answer a decision below, the build follows the spec text; where the spec cannot work as
written I stop and ask. Claude Code runs nothing online (spec + CLAUDE.md), never creates, reads, prints or
lists the contents of key.properties or any keystore, and never runs a release build that would sign with a
real key (section 2).

## 0. Blockers and state

| Spec 15 needs | Today (2026-10-30) | Effect |
|---|---|---|
| "Spec 14 is done and its checklist passed" | Spec 14's offline parts are built; staging never ran (specs 09-12a missing) | The production runbook can be written; nothing can be launched |
| health: "a simple Store read" in a deployed function | No store_factory / PgStore (spec 12a): index.ts files use depsFromEnv (FakeStore or 503) | health can be written and tested on FakeStore; on a real project it waits for 12a |
| health: "rate limit 60 per minute per IP hash" | No rate_limit.ts / Store.hitRateLimit (spec 09 / 12 hit_rate_limit) | Needs the spec 09 rate limiter (D212) |
| Mailer selection used by alerts-check | alerts-check / alerts-list functions not built (spec 11 has only _shared parts) | ResendMailer + mailerFromEnv are built and tested; the wiring into alerts-check happens when spec 11's function exists |
| `git check-ignore` (acceptance) | D:\BDPay is not a git repository; there is no root .gitignore | The check runs in a throwaway repo in the scratch folder (D215) |

- D210. **Build order.** A (recommended): build now everything spec 15 lists that does not need the missing
  backend: ResendMailer + selection, heartbeat fields, the Kotlin/Dart update card, settings links, Gradle
  signing, .gitignore, the three pay page site files + footer, the three ops files, the repo-scan additions;
  health written against Store + the spec 09 rate limiter interface, its rate-limit part waiting (D212).
  B: wait for specs 09-12a and 14.

## 1. Files

[CHANGED nn] = an earlier spec's file.

### Backend (supabase/functions)
- [CHANGED 11] _shared/mailer.ts - ResendMailer (fetch POST https://api.resend.com/emails, Authorization Bearer
  RESEND_API_KEY, JSON {from: ALERT_FROM_EMAIL, to: [to], subject, text}, AbortSignal.timeout(10 000);
  2xx -> "sent", anything else / timeout / network error -> "failed"; reads no response body, logs nothing) and
  mailerFromEnv(env, log) -> {mailer, configured}: BDPAY_FAKE_MAILER=1 -> FakeMailer; RESEND_API_KEY set ->
  ResendMailer (ALERT_FROM_EMAIL required, D216); neither -> FakeMailer + one log entry with code
  "mailerNotConfigured" (D217). Env comes in as a function argument (core files never read Deno.env).
- _shared/health.ts - handle(req, deps): GET only (405 otherwise); rate limit 60/min per SHA-256(IP) (D212);
  Store read (D211) -> 200 {ok: true, db: true, time} or 503 {ok: false, db: false}; no user data; logs only the
  fixed entry; Cache-Control: no-store.
- health/index.ts - serveFunction wiring like the others.
- [CHANGED 08] _shared/heartbeat.ts - adds latestAppVersion and appDownloadUrl to the 200 answer only when both
  are configured and valid (D218); otherwise the fields are absent.
- [CHANGED 08] _shared/http.ts - Deps gains `release?: {latestAppVersion?: string; appDownloadUrl?: string}`.
- [CHANGED 08] _shared/fake_store.ts - depsFromEnv fills `release` from LATEST_APP_VERSION / APP_DOWNLOAD_URL
  (the only place that reads env, as today).
- tests/resend_mailer_test.ts - stub fetch: 2xx sent, 500 failed, 401 failed, timeout failed (fake timer /
  never-resolving fetch + abort), network error failed; request shape (URL, method, headers, body); no log line
  and no thrown error carries the address, subject, body or key.
- tests/mailer_select_test.ts - the three selection rules + "mailerNotConfigured" logged once, without values;
  BDPAY_FAKE_MAILER=1 wins over RESEND_API_KEY.
- tests/health_test.ts - 200 shape; Store throwing -> 503 {ok:false, db:false}; 61st call in a minute from one IP
  -> 429; another IP still 200; POST -> 405; no merchant data in the body.
- [CHANGED 08] tests/heartbeat_test.ts - fields present when both env values set; absent when either is unset
  or invalid; old fields unchanged.
- [CHANGED 08] tests/boundaries_test.ts - CORE gains health; INDEX gains health/index.ts.
- [CHANGED 08] tests/logging_test.ts - health paths added; mailer selection log has the fixed keys only.
- [CHANGED 14] tests/repo_scan_test.ts - NO_VERIFY_JWT gains health: true; the same deploy-list check runs over
  ops/production_runbook.txt; every production runbook step ends with "check:"; release_checklist lines are
  all "[ ] yes / [ ] no"; new secret patterns: Resend keys (re_ + 20+ chars), Supabase project hosts
  ([a-z]{20}.supabase.co), *.pages.dev, and any domain written in place of REPLACE_ME (D221).

### Kotlin (the heartbeat answer is read by the native HeartbeatWorker, not by Dart - D213)
- [CHANGED 13a] HeartbeatRun.kt - reads latestAppVersion / appDownloadUrl from a 200 answer and saves them
  (both or neither; an answer without them clears them, so removing the env value removes the card).
- [CHANGED 13a] QueueRow.kt (PipelineConfig) - two optional properties with default no-op setters (FakeConfig
  unchanged).
- [CHANGED 13a] DeviceConfig.kt - stores them; changes fire the "pipeline" event.
- [CHANGED 13a] PipelineState.kt - toMap gains latestAppVersion and appDownloadUrl.
- [CHANGED 13a] PipelineRunTest.kt / PipelinePureTest.kt - saved when present, cleared when absent, a 200 without
  them changes nothing else; PipelineState map keys.

### Dart (app/)
- [CHANGED 13a] lib/domain/models/pipeline_state.dart - latestAppVersion, appDownloadUrl from the map.
- lib/domain/update_rules.dart - pure: isNewer(latest, running) on "major.minor.patch" (build suffix "+n" and
  anything after ignored; unparsable -> false); showUpdate(state, running) = url is https and isNewer.
- lib/features/home/widgets/update_card.dart - emerald card "নতুন ভার্সন {v} এসেছে" + "ডাউনলোড করুন", opens the
  URL through the existing UrlOpener (behind a repository/provider, so the screen does not import
  data/supabase - secrets_and_boundaries_test).
- [CHANGED 02] lib/features/home/home_screen.dart - shows the card (under the disconnected banner).
- [CHANGED 05] lib/features/settings/widgets/privacy_footer.dart - "গোপনীয়তা নীতি" and "শর্তাবলি" links (and the
  support line, D220), opening SITE_URL + "/privacy.html" / "/terms.html"; hidden when SITE_URL is empty (D219).
- [CHANGED 13] lib/core/app_config (or wherever SUPABASE_URL is read) - SITE_URL from --dart-define (D219).
- [CHANGED 01] lib/l10n/app_bn.arb - the new texts.
- test/domain/update_rules_test.dart - newer / same / older / "1.0.0+1" vs "1.0.0" / bad text / http URL.
- test/features/update_card_test.dart - card shown for newer; hidden for same, older, missing URL, missing
  version; tap opens the URL (fake opener).
- test/features/settings/legal_links_test.dart - both links open the right URLs; hidden without SITE_URL.

### Android build
- [CHANGED 06/13a] app/android/app/build.gradle.kts - release signing from app/android/key.properties (section 2).
  versionName / versionCode stay from pubspec.yaml (already 1.0.0+1 = versionName 1.0.0, versionCode 1; D222).

### Ignore rules
- .gitignore (new, project root) - section 3.
- [CHANGED 01] app/.gitignore - nothing removed; the root file covers the new lines (listed for completeness).

### Pay page site (pay_page/)
- privacy.html, terms.html - Bangla, red notice "আইনজীবীর পর্যালোচনা প্রয়োজন" at the top, placeholder text,
  support contact REPLACE_ME (D220), back link to the pay page.
- download.html - version, file size, SHA-256 as REPLACE_ME placeholders (filled by hand in the upload copy,
  D223), install steps in Bangla including "অজানা উৎস থেকে ইনস্টল চালু করুন", the "download only from this page"
  warning, support contact.
- [CHANGED 07] index.html - footer links to privacy.html and terms.html.
- [CHANGED 07] styles.css - footer and legal-page styles (existing tokens only).
- All three pages: the same CSP meta as index.html (connect-src 'self' - they call no API), no script at all
  (static text), viewport meta, layout that fits 320 px.
- pay_page/tests/site_pages_test.js - for privacy, terms, download and index: CSP meta present and equal to
  index.html's; no <script> with src outside 'self' and (for the three static pages) no script; no innerHTML /
  outerHTML / insertAdjacentHTML / document.write in any pay_page .js; footer links present; viewport meta;
  320 px static rules (no fixed width over 320 px, no min-width over 320 px in styles.css, long text breaks:
  overflow-wrap anywhere on the SHA-256).

### Ops documents
- ops/production_runbook.txt - steps 1-11 of the Contract, each with exact commands / dashboard paths and ending
  with "check:"; same secret rules as the staging runbook (hidden prompt + variable, crypto random, no
  --env-file, no link -p, unlink at the end); deploy list = staging's 17 + health (18). Staging / production
  separation built into the steps (D230):
  - step 2 starts with `Test-Path supabase\.temp\project-ref` -> must be False (not still linked to staging);
    its check line includes `supabase projects list` showing bdpay-prod as the linked project;
  - step 3 sets only what exists at that point; SHOPIFY_API_KEY / SHOPIFY_API_SECRET are set in step 7 from the
    NEW production Shopify app, PAY_PAGE_URL / PAY_PAGE_ORIGIN in step 6 from pay.<domain>; its check line
    compares `supabase secrets list` digests of PAY_TOKEN_SECRET, CRON_SECRET, SHOPIFY_API_SECRET with the
    staging digests you noted - all must differ (digests only, never values);
  - step 6: a production-only Resend domain and TWO Resend API keys created with "Sending access" for that
    domain only - one for RESEND_API_KEY (alerts), one typed into Dashboard > Auth > SMTP (login codes) - so
    each can be rotated alone; a separate Cloudflare Pages project (bdpay-pay-prod), never the staging one;
  - step 8: keytool run with passwords typed only at its prompts (never -storepass / -keypass on the command
    line), keystore under a folder outside the project and outside any cloud-synced folder (OneDrive etc.),
    key.properties written with Notepad (never Set-Content / echo with the passwords in the command), the
    project folder itself not cloud-synced while key.properties exists; check line = `keytool -list -v
    -keystore <path>` (password at the prompt) shows the alias, and you write the SHA-256 certificate
    fingerprint (public, not secret) into release_checklist.txt;
  - step 9: check line = `apksigner verify --print-certs <apk>` shows that same production fingerprint (never
    the staging one, D214) and `Get-FileHash -Algorithm SHA256 <apk>` equals the SHA-256 written on
    download.html; symbols copied to a private folder outside the project (D224);
  - step 10: the uptime monitor calls only GET /health and the pay page (no key in the monitor).
  - unlink step after the last supabase online command (as staging step 7).
- ops/release_checklist.txt - the 9 go / no-go lines, each "[ ] yes  [ ] no", plus date and signer lines.
- ops/incident_playbook.txt - the 7 cases, short steps; read-only SELECTs for lookups; the two hand-written
  data changes (device revoke + its audit row) given as exact single-row statements with WHERE id = '<id>' and
  marked as data changes. Secret rotation lists every place a value lives (D231): CRON_SECRET in `secrets set`
  AND Vault cron_secret (otherwise the schedules stop); PAY_TOKEN_SECRET (open pay links stop working);
  SHOPIFY_API_SECRET in Shopify first, then `secrets set`; RESEND keys in Resend (alerts key) or Auth > SMTP
  (login key); the service_role / anon keys through Dashboard > API Keys (a new anon key means a new APK
  build). Lookup query output stays on screen: never pasted into tickets, chats or repo files (it can hold
  TrxIDs and payer numbers).
- [CHANGED 14] ops/staging_runbook.txt - step 9 changes because release builds now need key.properties (D214).

## 2. Release signing without Claude Code touching key.properties

In app/android/app/build.gradle.kts (Kotlin DSL; the spec says build.gradle - D222):

```kotlin
import java.util.Properties

// Spec 15: release signing from app/android/key.properties, written by hand (ops/production_runbook.txt step 8).
// Never in the repo (.gitignore). Gradle reads it ONLY when a release task was asked for (D229), so debug
// builds and unit tests - the only builds Claude Code runs - never open it. Nothing here prints its values.
val keyPropertiesFile = rootProject.file("key.properties")
val wantsRelease = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
val keyProperties = Properties().apply {
    if (wantsRelease && keyPropertiesFile.isFile) keyPropertiesFile.inputStream().use { load(it) }
}
val releaseKeyNames = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingReleaseKeys = releaseKeyNames.filter { keyProperties.getProperty(it).isNullOrBlank() }

android {
    signingConfigs {
        if (missingReleaseKeys.isEmpty()) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            // No debug-key fallback: a release APK is always signed with the release key or not built.
            if (missingReleaseKeys.isEmpty()) signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Fails only release packaging, with a clear message that names missing keys, never values.
tasks.matching { it.name == "packageRelease" || it.name == "bundleRelease" }.configureEach {
    doFirst {
        if (!keyPropertiesFile.isFile) {
            throw GradleException("Release signing: android/key.properties not found. Create it by hand - see ops/production_runbook.txt step 8. Debug builds do not need it.")
        }
        if (missingReleaseKeys.isNotEmpty()) {
            throw GradleException("Release signing: android/key.properties is missing: ${missingReleaseKeys.joinToString()}.")
        }
        if (!file(keyProperties.getProperty("storeFile")).isFile) {
            throw GradleException("Release signing: the storeFile named in android/key.properties does not exist.")
        }
    }
}
```

- Debug builds and unit tests never open the file: it is read only when a requested task name contains
  "Release" (`flutter build apk --release` asks Gradle for assembleRelease; `flutter build apk --debug` and
  `testDebugUnitTest` do not), and the packaging check sits in packageRelease / bundleRelease.
- Gradle's configuration cache must stay off (it is off today; gradle.properties does not enable it): with it on,
  values read at configuration time - the passwords - would be stored under .gradle/configuration-cache. The
  build file gets a comment saying so, and repo_scan_test.ts fails if any gradle.properties enables
  org.gradle.configuration-cache (D229).
- Claude Code's only contact with the file is an existence test (`Test-Path app\android\key.properties`), never
  a read, list of contents, copy or create. The same for keystores: only a name search (*.jks, *.keystore, *.p12
  inside the project must find none), never opened. The acceptance test "release build fails with a clear message" is
  run by me ONLY when that test says the file does not exist; if it exists I skip the release build and ask you
  (running it would read your real key through Gradle and sign).
- The error messages name keys, never values; storeFile's path is not printed either.
- The keystore itself lives outside the project (runbook step 8: for example D:\bdpay-keys\, plus an offline
  copy); key.properties holds an absolute storeFile path.

## 3. .gitignore lines (new root .gitignore)

```
# Spec 15: secrets, keys and signing - never in the repo.
.env
.env.*
**/.env
**/.env.*
key.properties
**/key.properties
*.jks
**/*.jks
*.keystore
**/*.keystore
*.p12
**/*.p12
# Flutter obfuscation symbols (--split-debug-info=build/symbols, run in app/): keep privately, never commit.
build/symbols/
**/build/symbols/
# Supabase CLI link state (project ref, pooler URL).
supabase/.temp/
supabase/.branches/
# Build output.
build/
**/build/
.dart_tool/
**/.dart_tool/
node_modules/
```

The existing app/.gitignore and app/android/.gitignore stay; they already cover key.properties, *.jks, *.keystore
and /build/, and the root file adds the rest for the whole project.

## 4. Acceptance criteria -> test or check

| Criterion | Test or check | Runs now? |
|---|---|---|
| deno test: ResendMailer 2xx sent, 500 failed, timeout failed, nothing logged | resend_mailer_test.ts | yes |
| deno test: mailer selection rules | mailer_select_test.ts | yes |
| deno test: health ok / 503 | health_test.ts (FakeStore, a throwing store) | yes |
| deno test: health rate limit | health_test.ts | after D212 |
| deno test: heartbeat fields present and optional | heartbeat_test.ts | yes |
| Edge: Resend down -> alerts stay open and retry; health stays green | resend_mailer_test (failed) + spec 11's existing "mail failed -> retried" test with ResendMailer stubbed failing; health_test (health does not use the mailer) | yes (alerts part when alerts-check exists) |
| Edge: APP_DOWNLOAD_URL not set -> no card | heartbeat_test (field absent) + update_card_test (missing URL) + HeartbeatRunTest (cleared) | yes |
| Edge: an older app ignores the new heartbeat fields | HeartbeatRunTest: the 13a run with extra fields behaves exactly as before; the pre-13a app never called heartbeat (noted) | yes |
| flutter test: update card newer / same / older / missing URL | update_rules_test + update_card_test | yes |
| flutter test: privacy / terms links | legal_links_test | yes |
| flutter build apk --debug succeeds | `cd app; flutter build apk --debug` | yes |
| Release build fails with a clear message without key.properties | `Test-Path app\android\key.properties` = False, then `cd app; flutter build apk --release` -> exit code 1 and the "Release signing: android/key.properties not found" text | yes (only when the file is absent) |
| Pay page tests pass | `deno test pay_page/tests` (existing + site_pages_test.js) | yes |
| privacy / terms / download: no innerHTML, no outside scripts | site_pages_test.js | yes |
| ... work at 320 px | site_pages_test.js static rules + a manual look in Chrome DevTools at 320 px (I give the steps; I cannot open a browser here without your yes) | static yes / manual you |
| git check-ignore confirms key.properties, a .jks, build/symbols, .env | in a throwaway repo in the scratch folder: copy the root .gitignore, `git init`, `git check-ignore -v --no-index` on the path names app/android/key.properties, x/release.jks, app/build/symbols/a, supabase/functions/.env.local, .env -> all ignored. --no-index needs no files, so no dummy key or env file is created anywhere; no git repo is made in the project. Asked before running (it writes in the scratch folder, outside the project - CLAUDE.md) | yes, after your yes (D215) |
| Debug builds and unit tests never read key.properties | review of the wantsRelease guard + repo_scan_test.ts: build.gradle.kts loads key.properties only inside the wantsRelease condition; no gradle.properties enables the configuration cache | yes |
| Staging and production never share secrets, Shopify apps, Pages projects or keystores | production runbook check lines: secrets digests differ from staging's (step 3), separate Shopify app (step 7), separate Pages project (step 6), APK certificate = production fingerprint (step 9); release_checklist lines | you, when running the runbook |
| No release step deletes data | repo_scan_test.ts over the three ops files: no DELETE / DROP / TRUNCATE / `supabase db reset` / `Remove-Item` / `flutter clean` in any command line | yes |
| No secrets or real URLs in code | repo_scan_test.ts (with the D221 patterns) | yes |
| The three ops files exist; every runbook step has a "check" line | repo_scan_test.ts (production runbook 1-11 each ending with "check:", the unlink step present, the 18-function deploy list; staging runbook still passes its own checks after the D214 change; release checklist: the 9 spec lines, each "[ ] yes  [ ] no"; playbook: the 7 cases) | yes |
| Runbooks keep secrets out of files and history | repo_scan_test.ts over ops/production_runbook.txt: no secret name followed by a literal value, no --env-file, no `link -p`, no keytool -storepass / -keypass, no Set-Content / Out-File / echo writing key.properties | yes |
| ResendMailer never logs address, subject or body; no email content leaves the mailer except to Resend | resend_mailer_test (recording logger empty; thrown errors caught; no console call in mailer.ts - boundaries "no console" test) | yes |
| No secret / key / password / keystore in the repo | repo_scan_test.ts + a file-name search for *.jks, *.keystore, *.p12, key.properties (names only, never opened) | yes |
| deno check / lint / fmt, flutter analyze, all tests pass | the full run | yes |
| You complete release_checklist.txt with all yes | you | before the first merchant |

## 5. Unclear or wrong in the spec

Blocking: D210 (order), D212 (rate limiter), D214 (staging build), D219 (where the legal links point).

- D211. **"A simple Store read" for health.** getParserRules exists on every Store, but on the real database it
  fails when no active rules row exists, which would report the database as down. Proposal: use getParserRules
  and say so (staging/production always have active rules after runbook step 2); alternative: a new Store.ping()
  method (a Store interface change in spec 12a's PgStore - needs your yes).
- D212. **Health's rate limit needs the spec 09 rate limiter** (rate_limit.ts + Store.hitRateLimit /
  hit_rate_limit), which does not exist. A per-instance in-memory counter would not hold across Edge Function
  instances and would reset on every cold start. Proposal: health takes the spec 09 RateLimiter interface; until
  spec 09 exists, the tests use a fake limiter and the deploy waits. Also: the client IP comes from
  x-forwarded-for (first entry) on Supabase; a missing header hashes as "unknown" (all such callers share one
  bucket - note).
- D213. **The heartbeat answer never reaches Dart.** Since spec 13a the heartbeat is sent by the native
  HeartbeatWorker; Dart only sees getPipelineState. So "device-heartbeat response adds latestAppVersion ..."
  needs Kotlin changes (save the two values, expose them in the pipeline state) besides the Dart card - five
  13a files change (section 1). The spec lists only the server and the app card.
- D214. **Staging runbook step 9 breaks.** It builds a release APK signed with the debug key; after section 2 a
  release build without key.properties fails (by design). Options: A (recommended) a separate staging keystore
  for staging only (its own key.properties written by hand before the staging build and replaced by the
  production one for production builds - the runbook says to keep the two keystores in separate folders and
  check which one key.properties names before every release build); B build the staging APK with
  `flutter build apk --profile` (debug-signed, close to release but not identical: no R8 shrinking test).
  I change ops/staging_runbook.txt step 9 accordingly.
- D215. **"git check-ignore" needs a git repository; D:\BDPay is not one.** Proposal: the check runs in a
  throwaway repo in my scratch folder with a copy of the root .gitignore (no git repo is created in the
  project). If you want the project itself under git, that is your step (`git init` is not in the spec).
- D216. **ALERT_FROM_EMAIL missing while RESEND_API_KEY is set.** Proposal: treated as "not configured" (FakeMailer
  + the warning), not as a ResendMailer that fails every send.
- D217. **"one warning log line 'mailer not configured'"** - the spec 08 logger only accepts {fn, requestId, code,
  merchantId} (logging_test checks the keys). Proposal: code = "mailerNotConfigured" in that shape.
- D218. **Heartbeat values are not checked by the spec.** Proposal: LATEST_APP_VERSION must match
  ^\d+\.\d+\.\d+$ and APP_DOWNLOAD_URL must be https://; otherwise both are left out (no card), so a typo in a
  secret cannot send merchants to an http:// or broken link. The app checks https again before opening.
- D219. **The legal links need an address** but the app has only SUPABASE_URL and the anon key as
  --dart-define (spec 13). Proposal: a third optional --dart-define SITE_URL (for example https://pay.<domain>);
  empty -> the two links are hidden. Alternative: send the site URL in the heartbeat answer (more server
  config). Needs your choice.
- D220. **Support contact** is required by release_checklist ("written in the app settings footer and on
  download.html") but not in the spec's Scope. Proposal: on download.html, privacy.html and terms.html as a
  REPLACE_ME placeholder you fill in the upload copy; in the app a fourth optional --dart-define SUPPORT_CONTACT
  shown in the settings footer when set. Needs your yes (the app part is a small addition).
- D221. **"No real URLs in code (only environment names and REPLACE_ME)"** - the repo legitimately contains
  documentation URLs (Shopify admin paths, Resend's API endpoint, http://127.0.0.1 for local). Proposal: the
  scan rejects deployment hosts (Supabase project hosts, *.pages.dev, your domain if written) and allows API
  endpoints of providers and localhost.
- D222. **File names and version.** The project uses build.gradle.kts (Kotlin DSL), not build.gradle, at
  app/android/app/; key.properties is app/android/key.properties. versionName 1.0.0 / versionCode 1 already come
  from pubspec.yaml (1.0.0+1) and app_info_test keeps the app's own version text equal - no change.
- D223. **The APK on Cloudflare Pages.** Pages allows at most 25 MiB per file; a universal release APK (three
  ABIs) can be close to or over that. Proposal: build with --split-per-abi and publish the arm64-v8a APK (and
  armeabi-v7a for old phones) with one SHA-256 each on download.html; or host the APK in Cloudflare R2 and link
  it. The runbook checks the size (`(Get-Item <apk>).Length`) before uploading.
- D224. **Symbols in app/build/symbols are deleted by `flutter clean`.** The runbook copies them right after the
  build to a private folder outside the project, named by version (needed to read crash traces later).
- D225. **"A test alert email arrives from production"** has no trigger in the spec (alerts only send on real
  conditions). Proposal: the runbook makes one on purpose: with the pilot store connected and no device signed
  in for 30 minutes, noActiveDevice opens and emails you; or switch the phone off for 16 minutes (phoneSilent).
- D226. **R8 / obfuscation on release.** A release build shrinks Kotlin code; WorkManager workers, the SMS
  receiver and the channel are referenced by name. WorkManager's own keep rules cover workers, the manifest
  keeps the receiver; the release check is the pilot run on production (release_checklist line "one full real
  payment"). Noted, no keep rules added unless that run fails.
- D227. **The incident playbook's device revoke is a hand-written UPDATE** plus an audit_log INSERT in Studio. It
  changes data (allowed: nothing is deleted). The playbook gives single-row statements with WHERE id = '<id>' and
  tells you to run the SELECT first.
- D228. **Spec 15 Assumption "spec 14 done and passed" is not true yet** (D210); the production runbook's
  "before you start" lists spec 14's checklist as the first gate, as release_checklist does.

- D229. **Gradle would read key.properties on every build**, including the debug builds and unit tests Claude
  Code runs, if it is loaded at configuration time unconditionally. Fixed in section 2 (read only for
  release tasks; configuration cache stays off and is checked).
- D230. **Production runbook order would mix apps.** The Contract's step 3 sets SHOPIFY_API_KEY / SECRET before
  step 7 creates the separate production Shopify app, which invites pasting the staging values. The runbook sets
  them in step 7 from the production app, sets PAY_PAGE_* in step 6, and compares secret digests with staging.
- D231. **Rotating CRON_SECRET only with `secrets set` breaks the schedules** (Vault cron_secret still holds the
  old value -> every cron call gets 401). The playbook rotates both.
- D232. **"Untested operators turned off by default"** (release checklist) has no mechanism: the app's default
  operator set is all four (spec 05), and spec 15's Scope adds no setting. Options: A you switch them off per
  merchant during onboarding (checklist line answered by a runbook step, no code); B a build-time list of
  offered operators (a new feature - outside Scope, needs a spec 15a). Recommended A for the pilot.
- D233. **Email content at Resend.** Resend keeps sent emails (to, subject, text) in its dashboard logs; spec 11
  already keeps TrxIDs, amounts and numbers out of alert texts, and the login code email holds only the code.
  privacy.html's placeholder text names Resend as the email processor so the lawyer sees it.
- D234. **Outside Scope, marked:** the SUPPORT_CONTACT app define (D220, only with your yes), Store.ping (D211
  alternative, only with your yes), Cloudflare R2 (D223 alternative, your account, your choice). Nothing in this
  plan submits to Google Play, the Shopify App Store or bills anyone; every online step is in the runbook.

## 6. Order of work (after your answers)

0. Ask before: the throwaway-repo check-ignore run (scratch folder, D215); the release-build failure check if
   it would download anything new.

1. Backend: ResendMailer + selection, heartbeat fields, health (FakeStore, fake limiter) + tests; deno
   check / lint / fmt / test.
2. Kotlin pipeline fields + tests; Dart model, update rules, card, links + tests; flutter analyze / test; Kotlin
   tests.
3. Gradle signing; `flutter build apk --debug`; the release-failure check (only if key.properties is absent).
4. Root .gitignore + the throwaway-repo check-ignore run.
5. Pay page pages + footer + site_pages_test.js; `deno test pay_page/tests`.
6. Ops documents (production runbook, release checklist, incident playbook) + staging runbook step 9 (D214) +
   repo_scan_test additions; full run of every check.

## 7. Review changes (2026-10-30)

- Scope: outside-Scope items listed in one place (D234: SUPPORT_CONTACT, Store.ping, R2 - each only with your
  yes); "untested operators off by default" has no code in Scope -> handled as an onboarding step (D232).
- Secrets and keys: Gradle reads key.properties only for release tasks, so the debug builds and unit tests I
  run never open it; configuration cache must stay off (D229); keystore files are only searched by name; keytool
  passwords only at its prompts, key.properties written in Notepad, keystore and project outside cloud-synced
  folders; two production-only Resend keys with sending access to one domain; email content at Resend noted for
  the privacy text (D233); playbook lookup output never copied anywhere; the check-ignore run uses path names
  only (no dummy key or env files).
- Staging / production: production runbook checks it is not still linked to staging, sets Shopify secrets only
  from the new production app, compares secret digests with staging, uses its own Pages project and Resend
  domain, and checks the APK certificate is the production fingerprint (D230, D214); secret rotation covers
  Vault's cron_secret too (D231).
- Checks added: no-read guard in the Gradle file, staging/production separation lines, no data-deleting command
  in the ops files, no secrets in runbook commands (production), mailer never logs; the scratch-folder
  check-ignore run is asked first (CLAUDE.md: files outside the project).
