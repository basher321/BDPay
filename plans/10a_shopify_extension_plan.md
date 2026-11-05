# Plan 10a - Shopify app config and checkout extension

Spec: specs/10a_shopify_extension.md (uses spec 07's pay page and spec 10's shopify-paylink)

Status found (2026-10-29)
- Node.js v24.21.0 and npm 11.19.0 are installed. The Shopify CLI is NOT installed (`shopify` not found).
- shopify_app/ does not exist.
- Spec 10's backend is only partly built (its pure parts); shopify-paylink does not exist yet, and specs 08/09 are
  missing. The extension can be built and tested on its own (DEV_FAKE), but nothing live works until spec 10 is done.
- I checked Shopify's docs online for target names, the order APIs and CLI flags (sources at the end). I could not
  run the CLI, so every flag below marked "confirm with --help" must be checked before use.

Decisions needed before anything runs
- D46. **The install flow the spec wants may conflict with the webhooks it wants.** Spec 10 installs through the
  backend's authorization-code OAuth. In current Shopify app config that usually means
  `[access_scopes] use_legacy_install_flow = true`. But the CLI has been reported to REJECT app-specific webhook
  subscriptions in shopify.app.toml when that flag is on ("Remove 'use_legacy_install_flow = true' ... or continue
  using shop-specific webhooks with the legacy install flow"). So "legacy OAuth" + "webhooks in the toml" may not both
  be possible. The spec says tell you before setting it. Options:
  A legacy flow ON, webhooks NOT in the toml: the backend would have to register orders/create, orders/cancelled and
    app/uninstalled per shop after OAuth (a backend change - outside 10a's scope, needs a spec 10 change); compliance
    topics would still need to be in the toml (check that this is allowed with the legacy flag).
  B Shopify-managed install (no legacy flag) with the webhooks in the toml as the spec says: the backend would then get
    tokens by token exchange instead of the authorization-code callback (a spec 10 change).
  C try the spec's exact config with the flag and see what the CLI says, then decide.
  Options A and B are spec 10 (backend) changes, outside 10a's scope: this plan builds none of them. Nothing is set
  until you choose.
- D47. **The Order status target is not a checkout UI extension target.** Shopify's docs list
  `purchase.thank-you.block.render` under checkout UI extensions and `customer-account.order-status.block.render` under
  customer account UI extensions. The spec asks for ONE checkout UI extension with both targets. Shopify's unified
  `type = "ui_extension"` may accept both targets in one extension (older docs list the order-status target under
  checkout UI extensions too) - to be confirmed when generating. If the CLI refuses, the fallback is two extensions
  in one folder (bdpay-pay-box for Thank-you, bdpay-order-status for Order status) sharing src/ - a change to the
  spec's folder list, so it needs your yes.
- D48. **nextRetryDelay(attempt) can't know which rule applies.** notReady retries 10 times, error retries 2 times;
  the attempt number alone can't tell them apart. Proposal: nextRetryDelay(result, attempt) -> 3000 or null.
- D49. **Installs and logins (downloads and outward actions - your yes, or you run them):**
  - installing the Shopify CLI (`npm install -g @shopify/cli@latest`), a download;
  - `shopify app init` logs in to your Partner account in a browser and creates the app there (outward action), and
    `npm install` inside the new app downloads Preact and Shopify's UI packages.
  Proposal: you run these three yourself with the `!` prefix (they need your browser login anyway); I write files.
- D50. **"No real URL in shopify_app" vs template files.** The CLI template brings files with real URLs (README links to
  shopify.dev, package-lock.json registry URLs) and node_modules/. Proposal: the search covers only files we own or
  edit (toml, src/, locales/, MERCHANT_SETUP_BN.txt, tests/), and I trim the template README to a short local note
  without links. node_modules/, package-lock.json and .shopify/ are excluded (generated, not committed config).
- D52. **Type check tool.** The criterion asks for "no type errors". The CLI bundler (esbuild) does not type-check. If
  the generated template already lists `typescript`, `npx tsc --noEmit` uses it (no new package). If not, options:
  A add `typescript` as a devDependency (a package the spec does not name - your yes); B report the type check as not
  possible and rely on the bundle build.
- D53. **Linking writes real values.** `shopify app config link` (your step) puts the real client_id and URLs into the
  app config. To keep the committed shopify.app.toml on REPLACE_ME values, the plan asks the CLI to write a separate
  named config (it offers `shopify.app.<name>.toml`), which goes in .gitignore together with `.env` and `.shopify/`.
  The same applies to src/config.ts once you put the real FUNCTIONS_URL in: the search criterion is checked on the
  files as I hand them over (all REPLACE_ME).
  Also: `shopify app dev` writes the dev store address (dev_store_url) and, for apps with a web part, tunnel URLs into
  the ACTIVE config file. With the linked config active, those real values land in the gitignored linked file, not
  in shopify.app.toml. The built bundle (`dist/` and similar output) contains config.ts's value too, so build output
  folders are gitignored as well and excluded from the search.
- D54. **Template packages.** The spec allows only Preact and Shopify's UI packages. The template's package.json may
  bring others (e.g. `@preact/signals`, `@shopify/ui-extensions-tester`, typescript). Each one is listed and you decide
  before `npm install`; nothing outside that list is added by me.
- D51. **Order status page needs "new customer accounts".** Customer account UI extensions render on the Order status
  page only when the store uses new customer accounts (to confirm in the docs and on the dev store). MERCHANT_SETUP_BN
  may need a step for it - its text is fixed by the spec, so I would only add it with your yes.

## 1. Shopify CLI commands (not run; D49 says who runs them)

Run from D:\BDPay. Confirm every flag with `--help` first.
1. `npm install -g @shopify/cli@latest`
   Installs the `shopify` command globally (download).
2. `shopify app init --template none --name BDPay --path D:\BDPay`
   `--template none` = an app with no web app part (extension-only); it asks you to log in and creates the BDPay app in
   your Partner account. It creates `D:\BDPay\bdpay\` (checked first: no folder of that name exists) with
   shopify.app.toml, package.json, extensions/ (empty), .gitignore, README.md. Then that folder is renamed to
   D:\BDPay\shopify_app - a rename only, so no empty folder is left behind and nothing is deleted.
   (`--path` is the parent folder; the CLI names the app folder from --name.)
3. `cd shopify_app` then `shopify app generate extension --template checkout_ui --name bdpay-pay-box --flavor preact`
   (template id and flavor name to confirm with `shopify app generate extension --help` / the interactive list; the
   docs say UI extensions are scaffolded with Preact by default).
   Creates extensions/bdpay-pay-box/ with shopify.extension.toml, a src/ entry file, locales/en.default.json (and
   possibly other locale files - section 5, item 7), package.json, tsconfig.json.
4. `npm install` inside shopify_app (downloads Preact + @shopify/ui-extensions packages). Before it runs, I list every
   package in the generated package.json files; anything that is not Preact or a Shopify UI/CLI package (for example
   an analytics or helper library) is reported to you and not installed without your yes (D54).
5. Build check: `shopify app build` (bundles the extension) and `npx tsc --noEmit -p extensions/bdpay-pay-box` for
   the type check - the bundler alone does not report type errors, so both are needed for the criterion.
   `tsc` must come from the template's own devDependencies; if the template has no `typescript` package, adding it
   would be an extra package (CLAUDE.md) -> D52.
6. You, later: `shopify app config link` (fills client_id and the REPLACE_ME values) and `shopify app dev`.

## 2. Files

New (shopify_app/)
- shopify.app.toml - name BDPay, embedded = false, scopes read_orders,write_orders, application_url and redirect URL as
  REPLACE_ME_..., webhooks per the spec (api_version 2026-10; orders/create, orders/cancelled, app/uninstalled with
  include_fields ["id", "admin_graphql_api_id"]; compliance topics in their own subscription entry). Final shape
  depends on D46.
- extensions/bdpay-pay-box/shopify.extension.toml - type ui_extension, api_version 2026-10, two [[extensions.targeting]]
  entries (section 3), [extensions.capabilities] network_access = true and nothing else, localization. The template's
  own default capabilities (for example api_access or block_progress, if it adds them) are taken out, so
  network_access is the only one.
- extensions/bdpay-pay-box/src/view_logic.ts - pure, no imports: PaylinkResult, decideView, nextRetryDelay (D48),
  isSafePayUrl (https only), parsePaylinkAnswer (JSON -> PaylinkResult; keeps only status / payUrl / sessionStatus).
- extensions/bdpay-pay-box/src/config.ts - FUNCTIONS_URL = "REPLACE_ME_FUNCTIONS_URL"; DEV_FAKE = null (off) or one of
  the result kinds, to see each view in `shopify app dev`. The fake ready answers use the reserved, never-real address
  `https://pay.example.invalid/?t=dev` (`.invalid` can never resolve), so the payNow/pending views can be seen without
  any real URL in the folder.
- extensions/bdpay-pay-box/src/paylink.ts - one call: fresh `await shopify.sessionToken.get()` every time, POST
  FUNCTIONS_URL/shopify-paylink {orderId}, 10 s timeout; maps the answer to PaylinkResult (non-200, bad JSON, timeout,
  an unsafe payUrl, FUNCTIONS_URL still REPLACE_ME -> {status: "error"}); reads ONLY status, payUrl and sessionStatus
  from the answer and ignores any other field (so even a future backend field like an amount can never reach the
  view); never logs (no console.* at all) - the session token and payUrl (which holds the pay token) never appear in
  a log; with DEV_FAKE set, returns the fake answer and makes no request.
- extensions/bdpay-pay-box/src/PayBox.tsx - the shared box: runs the attempt loop (decideView + nextRetryDelay),
  renders the 7 views with Shopify web components (banner, button, link, spinner, text); all text via
  shopify.i18n.translate; stores nothing. What each view shows (section 6): only locale text; payUrl is used only as
  the button/link target and is never printed as text; no input field of any kind.
- extensions/bdpay-pay-box/src/ThankYou.tsx - target entry for the Thank-you block: order id from
  shopify.orderConfirmation.value.order.id.
- extensions/bdpay-pay-box/src/OrderStatus.tsx - target entry for the Order status block: order id from
  shopify.order.value.id.
- extensions/bdpay-pay-box/locales/en.default.json and bn.json - the same keys; Bangla text exactly as the spec.
- MERCHANT_SETUP_BN.txt - the 5 numbered steps exactly as the spec + the line "Check the Shopify menu names before
  release; they may change." (no URLs).
- .gitignore (template) - checked to contain `.env`, `.shopify/`, `node_modules/`, the build output folders (`dist/`)
  and the linked `shopify.app.*.toml` (D53); none of those files is ever opened by me (CLAUDE.md: never read .env).
- tests/view_logic_test.ts - every decideView rule and nextRetryDelay.
- tests/locales_test.ts - en.default.json and bn.json have exactly the same keys; no empty values; bn.json strings equal
  the spec's Bangla text.
- tests/setup_text_test.ts - MERCHANT_SETUP_BN.txt has the 5 steps and the "Check the Shopify menu names..." line.
- Template files from the CLI (package.json, tsconfig.json, .gitignore, README.md trimmed per D50).

Changed
- CLAUDE.md - one line under Folders: "- shopify_app/    Shopify app config and checkout extension" (the spec asks for it).

## 3. Extension target names

| Page | Target | Where found |
|---|---|---|
| Thank-you page (block) | `purchase.thank-you.block.render` | shopify.dev, checkout UI extensions, Targets (latest = 2026-10) |
| Order status page (block) | `customer-account.order-status.block.render` | shopify.dev, customer account UI extensions, Targets (latest = 2026-10); also listed under checkout UI extensions 2023-10 |
Order ids: Thank-you - `shopify.orderConfirmation.value.order.id` ("a globally unique GID that corresponds to the order in
the GraphQL Admin API", Order API page, only on purchase.thank-you targets). Order status - `shopify.order` (customer
account Order API). Both to confirm against the generated template's types (D47).

## 4. Acceptance criteria -> check

| Criterion | Check |
|---|---|
| deno test shopify_app/tests passes | `deno test shopify_app/tests` |
| every decideView rule | view_logic_test: notBdpay, alreadyPaid, ready+verified/open/pending/mismatch/expired/rejected |
| notReady at attempts 0, 9, 10 | view_logic_test: loading, loading, waitLonger |
| error at attempts 0, 1, 2 | view_logic_test: loading, loading, failed |
| nextRetryDelay null when no retry is due | view_logic_test: 3000 for notReady 0-9 and error 0-1; null for notReady 10+, error 2+, and every final view |
| builds with the Shopify CLI, no errors or type errors | `shopify app build` (bundle) + `npx tsc --noEmit` (types; D52) - after the D49 installs |
| no secret, token, API key value or real URL (only REPLACE_ME) | search of our files (D50): every `http(s)://` found must be a REPLACE_ME value or a `.invalid` test address; client_id and application_url are REPLACE_ME_...; no "shpat_/shpss_/shpca_/shprt_"; no 32-hex API-key-looking string; .env / .shopify / linked tomls are gitignored (D53) |
| en.default.json and bn.json have the same keys | locales_test |
| By hand: `shopify app dev` shows the box on both pages; DEV_FAKE shows each view | you, with the DEV_FAKE table in section 7 (which value shows which view, and how long to wait for waitLonger / failed) |
| Full live test | spec 14 |

Other rules checked too

| Rule | Check |
|---|---|
| Only network_access, no other capability | review shopify.extension.toml (template defaults removed) |
| shopify.app.toml as the contract says | review: name BDPay, embedded false, scopes exactly read_orders,write_orders, redirect URL REPLACE_ME/shopify-oauth-callback, webhooks api_version 2026-10, uri REPLACE_ME/shopify-webhooks, the 3 topics with include_fields [id, admin_graphql_api_id], the 3 compliance topics |
| "If the CLI does not allow include_fields ... tell me" / "tell me before setting a legacy install flag" | the CLI's answer to `shopify app config validate` (or the first deploy dry run) is reported to you before anything else is changed (D46) |
| ready with an unknown sessionStatus | view_logic_test: hidden (fails safe, never payNow) |
| Only Preact and Shopify packages | the package list from step 4 (D54) |
| Fresh session token before every call | review paylink.ts: sessionToken.get() inside the call, never cached |
| Never shows wallet number, amount or a TrxID form | review PayBox.tsx: no input field; the only data shown is from locale files; payUrl used only as a link target |
| No data stored, no third-party scripts, analytics or tracking | search: no localStorage / sessionStorage / storage API / analytics.publish; only Preact + Shopify packages in package.json |
| view_logic.ts has no imports | search |
| Only https payUrl is opened | view_logic_test for isSafePayUrl |
| Bundle within Shopify's size limit | the build output size against the limit in Shopify's current docs (to look up at build time; I won't guess a number) |
| Bangla texts exactly as the spec | locales_test compares bn.json to the spec's strings |
| All text from the locale files (no hard-coded text) | search of src/*.tsx: no Bangla characters and no English words inside JSX text or string props, only translate("...") keys |
| Order id from the order confirmation API (Thank-you) and the order API (Order status) | review ThankYou.tsx / OrderStatus.tsx |
| paid is shown only from the backend's answer | view_logic_test: only alreadyPaid or ready+verified give "paid" |
| The extension reads only status / payUrl / sessionStatus | a Deno test of the answer-mapping function (pure part of paylink.ts moved into view_logic.ts as parsePaylinkAnswer) with extra fields like amountPoisha / walletNumber - they are dropped |
| MERCHANT_SETUP_BN.txt matches the spec | a Deno test reads the file and checks the 5 steps and the marker line |
| CLAUDE.md Folders line added | search: the exact line is present once |
| No console logging (tokens, payUrl) | search: no `console.` in src/ |
| UTF-8 without BOM | search |

## 5. Unclear, or settings that may differ in the current CLI

1. Install flow vs webhooks -> D46.
2. One extension with both targets -> D47.
3. nextRetryDelay signature -> D48.
4. include_fields: check that shopify.app.toml webhook subscriptions accept `include_fields` for orders/create,
   orders/cancelled and app/uninstalled (the spec says tell you if not). app/uninstalled may not support it.
5. Compliance topics: put them in their own [[webhooks.subscriptions]] with `compliance_topics` and a full https uri
   (a reported CLI validation problem mixed them with normal topics).
6. `embedded = false` still needs application_url (REPLACE_ME). Check that an extension-only app may set embedded false.
7. The template may add other locale files (e.g. fr.json); the spec lists only en.default.json and bn.json. I will
   list any extra template files and ask before removing them (CLAUDE.md: no deleting without asking).
8. Network access must be approved in the Partner Dashboard (your step, per the spec).
9. Thank-you page: the order may not exist in the Admin API yet when the block renders -> the backend answers notReady
   and the box retries (spec rule). Matches spec 10 D42.
10. Session token in checkout/customer-account extensions: check its claims (aud, dest) match what spec 10's
    verifySessionToken expects (built: dest must be https://<shop>.myshopify.com).
11. Opening payUrl: Shopify components open external links in a new tab; check the button/link `href` behaviour in
    2026-10 (an external URL may need `target`/`external` attributes).
12. Order status page needs new customer accounts -> D51.
13. Spec 10 backend not finished: the extension can only be tested with DEV_FAKE until shopify-paylink exists.
14. CLAUDE.md: no packages beyond Preact and Shopify's UI packages (typescript only via D52); text only from locale
    files; no .env is read (the CLI may write one when linking - I won't open it, only check it is gitignored); no
    folder or many-file deletes (the init folder is renamed, extra template files only removed with your yes);
    downloads and outward actions only with your yes (D49).
15. **Default language.** CLAUDE.md says Bangla is the default; Shopify requires one `*.default.json` locale and the spec
    names `en.default.json`. Shopify picks bn.json for buyers whose checkout language is Bangla and falls back to
    English otherwise. The spec wins; noted.
16. **Colours.** Shopify's checkout components can't take custom colours, so the box follows the merchant's checkout
    branding, not BDPay's tokens. Expected; noted.

Sources checked (2026-10-29)
- https://shopify.dev/docs/api/checkout-ui-extensions/latest/targets
- https://shopify.dev/docs/api/customer-account-ui-extensions/latest/targets
- https://shopify.dev/docs/api/checkout-ui-extensions/2026-10-rc/target-apis/checkout-apis/order-api.md
- https://shopify.dev/docs/api/shopify-cli/app/app-init
- https://shopify.dev/docs/api/shopify-cli/app/app-generate-extension
- https://community.shopify.dev/t/compliance-topics-issue/18702
- https://github.com/Shopify/cli/issues/5505
- https://shopify.dev/docs/apps/build/security/app-security-checks/missing-compliance-webhooks
- https://shopify.dev/docs/api/customer-account-ui-extensions/latest/index.md

## 6. What each view shows (no wallet number, amount or TrxID form anywhere)

| View | Shown | Never shown |
|---|---|---|
| hidden | nothing | - |
| loading | a small spinner, no text | - |
| payNow | info banner, heading and text from locale keys, primary button with locale text; button target = payUrl | wallet number, amount, any input; payUrl as visible text |
| pending | info banner text, plain link with locale text; target = payUrl | same |
| paid | success banner text | button, amount, TrxID |
| waitLonger | locale text | - |
| failed | locale text | - |
The heading "...এখনই পেমেন্ট করুন এবং TrxID দিন" only TELLS the customer to enter the TrxID on the pay page; there is no
field for it in the extension. Wallet numbers, amounts and the TrxID form exist only on the pay page (spec 07).

## 7. DEV_FAKE: seeing each view by hand

| DEV_FAKE value in src/config.ts | View you should see |
|---|---|
| null (default) | real call - REPLACE_ME FUNCTIONS_URL makes it "error": loading, then failed after the 2 retries |
| "notBdpay" | hidden (nothing) |
| "alreadyPaid" | paid banner |
| "ready-open" | payNow (button opens https://pay.example.invalid/?t=dev, which will not load - expected) |
| "ready-pending" / "ready-mismatch" | pending banner + link |
| "ready-verified" | paid banner |
| "ready-expired" / "ready-rejected" | hidden |
| "notReady" | spinner for about 30 s (10 tries x 3 s), then the waitLonger text |
| "error" | spinner for about 6 s (2 retries), then the failed text |
DEV_FAKE must be back to null before any release build (a search check: DEV_FAKE = null in config.ts).

## 8. Review log

Review 1 against spec 10a and CLAUDE.md:
- Scope: no backend change, admin page or App Store work in the plan; D46 options A/B are now marked as spec 10
  changes this plan does not build. The temporary init folder was replaced by init in D:\BDPay + rename (no leftover
  folder to delete). Only network_access as capability. `typescript` for the type check may be an extra package -> D52.
- Secrets / URLs: linking writes the real client_id and URLs -> D53 (separate linked config, gitignored, with .env and
  .shopify/); the DEV_FAKE pay URL uses a reserved `.invalid` address; no console logging, so the session token and the
  payUrl (pay token) never reach a log; the search rule refined (REPLACE_ME or .invalid only, no key-looking strings).
- Views: added section 6; paylink answers are reduced to status / payUrl / sessionStatus (tested), so an amount or
  wallet field can never reach the box; payUrl is never shown as text; no input field exists.
- Criteria: the "no type errors" check needed tsc (the bundler doesn't type-check) -> D52. Added checks for: no
  hard-coded text, order-id sources, paid only from the backend, answer filtering, MERCHANT_SETUP text, the CLAUDE.md
  line, no console logging.
- CLAUDE.md: no extra packages (D52), never read .env, no folder deletes, downloads only with your yes; Bangla default
  vs en.default.json and checkout colours noted (spec wins / Shopify limit).

Review 2 (same questions, looking for what review 1 missed):
- Scope: the template may add capabilities (api_access, block_progress) -> removed so network_access is the only one;
  the template's package.json may bring packages beyond Preact/Shopify -> listed and decided by you before npm
  install (D54).
- Secrets / URLs: `shopify app dev` writes dev_store_url (and for web apps tunnel URLs) into the active config -> lands in
  the gitignored linked config, not shopify.app.toml; build output (dist/) holds config.ts's value -> gitignored and
  excluded from the search.
- Views: nothing new found; added a fail-safe rule (ready with an unknown sessionStatus -> hidden, tested).
- Criteria: added checks for the shopify.app.toml contents, reporting the CLI's answer about include_fields / the
  install flag before changing anything, the package list, and a DEV_FAKE table (section 7) so "each view can be seen
  once" has concrete steps; DEV_FAKE must be null in release (search). The size limit is looked up, not guessed.
- CLAUDE.md: "add no package the spec does not name" now covers the template's packages too (D54).
