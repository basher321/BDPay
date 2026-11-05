# Plan 07 - Customer pay page

Spec: specs/07_pay_page.md (uses money format and colour tokens from spec 01)
Status found:
- pay_page/ does not exist yet.
- **Deno is not installed** (`deno --version`: command not found). Python 3.12.10 is installed.
- **app/assets/fonts is empty**: the Noto Sans Bengali files were never added (spec 01 fell back to the system font).
- **specs/07_pay_page.md is cut off** in the Acceptance criteria ("A search of pay_page shows no innerHTML, outerHTML,").

Decisions taken (2026-10-29): D18 = install with winget (approved), D19 = B (system font fallback; no fonts/ folder
until files exist), D20 = still open (visible criteria used), D21 = yes, D22 = C (spec 13), D23 = B (fee note),
D24 = yes, D25 = yes.

Decisions needed before execution
- D18. **Install Deno?** The tests must run with `deno test`. Installing changes installed software, so it needs your yes.
  Options: A (recommended) you run `winget install --id DenoLand.Deno` yourself (or I run it after your yes);
  B I write the code and tests now, and nothing is run until Deno is installed.
- D19. **Font files are missing.** The spec says copy them from app/assets/fonts, which is empty. Options:
  A (recommended) you put NotoSansBengali-Regular.ttf, -Medium.ttf and -Bold.ttf in app/assets/fonts; I copy them to
  pay_page/fonts and use them (@font-face, font-src covered by default-src 'self');
  B ship without them now: the CSS lists "Noto Sans Bengali" first and falls back to the phone's own Bangla font.
  I will not download fonts (spec 01: "Do not download anything").
- D20. **The rest of the Acceptance criteria.** The file stops mid-sentence. Please paste the missing part; until then
  section 3 uses the criteria that are there plus my best reading of the cut line (no innerHTML / outerHTML /
  insertAdjacentHTML / document.write).
- D21. **Mock triggers for paths that otherwise can't be tested.** The mock has no way to return rateLimited, to fail
  with a network error, or to time out, so rules 4 and the "slow network" edge case can't be checked. Proposal: three
  extra mock TrxIDs, all marked MOCK: RATE1234 -> rateLimited; NETERR12 -> the request fails (network error);
  SLOW1234 -> the mock waits 15 s (hits the 10-second timeout). They pass isValidTrxId for bKash/Nagad/Upay.
- D22. **"rejected" has no screen.** CLAUDE.md's claim status includes rejected, and spec 03 lets the merchant reject a
  mismatch by hand, but Session.status has no "rejected". A customer whose payment was rejected would stay on the
  mismatch screen forever. Options: A add status rejected + a screen (needs your text); B map rejected to the
  mismatch screen; C leave it to spec 13 (the server would never send it until then). Recommended: A, text e.g.
  "পেমেন্ট বাতিল হয়েছে" / "দোকানে যোগাযোগ করুন। TrxID: {trx}" - your wording decides.
- D23. **Agent wallets make the customer pay a cash-out fee.** Cash Out to an agent costs the sender a fee (about 1.85%
  on bKash). The customer must send the exact amount, so either they pay the fee on top or the merchant gets less and
  the match may fail. This is a product question, not a code one. Options: A keep as spec (agent steps say Cash Out);
  B show an extra note on agent steps ("ক্যাশ আউট চার্জ আপনার অ্যাকাউন্ট থেকে কাটা হবে"); C don't offer agent
  wallets on the pay page. Your call; the plan builds A unless you choose otherwise.
- D24. **A one-operator mock token.** The spec's mock tokens all have 4 operators, so the "one operator -> no tabs"
  edge case can't be seen. Proposal: token demo-one (bKash only), marked MOCK. Without it, that rule is checked by
  code review only.
- D25. **Optional extra CSP line: `require-trusted-types-for 'script'`.** With it, Chrome makes innerHTML and the
  other HTML sinks throw, so an HTML mistake fails loudly instead of running. It is one more directive than the spec
  lists, so it needs your yes. Samsung Internet (Chromium) supports it; other browsers ignore it.

## 1. Files (all new; no earlier file changes)

pay_page/
- index.html - the single page: CSP meta tag, header (logo + "BDPay"), one <main> the screens render into, toast
  container, `<script type="module" src="app.js">`. No inline script or style.
- styles.css - colour tokens from spec 01 (em #00D09C, bg #080D1A, sf #10192D, cd #17233D, bd #233558, t1/t2/t3, ok,
  wa, er, operator text colours #F0559A #F9A940 #B565C0 #5B9BE6), @font-face (D19), cards, chips, buttons (min 44 px),
  body text 15 px+, spinner, toast; mobile-first, no horizontal overflow at 320 px.
- app.js - screens and events: loading, not found, open, pending, verified, mismatch, expired; operator tabs, copy,
  submit (busy guard), polling (visibilitychange pause/resume), countdown. All Bangla UI text sits in one STRINGS
  object at the top (see section 5, item 12). DOM rules (section 6): every node via createElement + textContent;
  attributes only from fixed values in the code; operator values from the server are checked against the 4 known
  operators before they pick a class or a step list; returnUrl is used only after isSafeReturnUrl; error objects are
  never shown, only fixed STRINGS. The page shows "verified" only when the server's status says so, never on submit.
- logic.js - pure ES module, no DOM: formatPoisha (whole-number math only: Number.isSafeInteger input, taka =
  Math.floor(p / 100) on integers, poisha = p % 100; no fractional money values anywhere), normalizeTrxId, isValidTrxId, formatCountdown, nextPollDelay, plus
  three small pure helpers the screens need: formatDhakaTime (verified screen, fixed UTC+6 like the app),
  isSafeReturnUrl (only https:, or http://localhost / 127.0.0.1 for testing), withTimeout(promise, ms).
- api.js - the interface: getSession, submitClaim, getStatus. Picks the implementation named in config.js and wraps
  every call in withTimeout(10 000 ms); a timeout or thrown error becomes a NetworkError the screens show as
  "ইন্টারনেট সংযোগ দেখুন".
- api.mock.js - "MOCK - replaced by the real API in spec 13". createMockApi({now}) (testable clock) + a default instance.
  The 5 demo tokens, USED1234, attempts 5 -> 0, and D21 triggers. Reuses logic.js isValidTrxId for invalidFormat.
- instructions.js - steps per operator x account type (8 entries), each a function (wallet, amount, orderRef) ->
  4-5 Bangla lines incl. "রেফারেন্স: {orderRef}"; merchant = "Make Payment"/"পেমেন্ট", agent = "Cash Out"/"ক্যাশ আউট";
  every entry marked "SAMPLE - check the wording in each operator's app". Steps say the PIN goes only into the
  operator's own app.
- config.js - `export const API = 'mock'` (and the future API origin, empty now).
- fonts/ - the 3 Noto Sans Bengali files copied from app/assets/fonts (only if D19 = A).
- tests/logic_test.js - every example in the spec + extra edge cases.
- tests/api_mock_test.js - all mock flows with a fake clock.
  Both use only Deno.test and `node:assert/strict` (built into Deno). No jsr:, npm: or https: imports, so running the
  tests downloads nothing.

## 2. Order of work

0. Your answers on D18-D25; Deno installed (D18).
1. logic.js + tests/logic_test.js -> `deno test pay_page/tests` green.
2. api.mock.js + tests/api_mock_test.js -> green.
3. config.js, api.js (timeout + error mapping), instructions.js.
4. index.html (CSP), styles.css, app.js: loading / not found -> open -> submit -> pending + polling -> verified /
   mismatch / expired -> countdown expiry -> copy + toast.
5. Fonts (D19).
6. Checks: deno test, the searches and the size check in section 3; serve locally and walk every URL in section 4.
7. You check on a phone (Chrome for Android, Samsung Internet) and at 320 px.

## 3. Acceptance criteria -> check

| Criterion | Check |
|---|---|
| deno test pay_page/tests passes | `deno test pay_page/tests` |
| formatPoisha examples: 125050 "৳ 1,250.50", 0 "৳ 0.00", 123456789 "৳ 1,234,567.89", 125000 "৳ 1,250.00"; negative throws (same rules as the app) | logic_test |
| normalizeTrxId: " 9k48 x7z2 " -> "9K48X7Z2"; "২৪০১০২০০১২৩" -> "24010200123" | logic_test |
| isValidTrxId: bkash/nagad/upay 8-12 letters or digits; rocket 8-14 digits only (7/8/12/13/14/15 lengths, letters in rocket) | logic_test |
| formatCountdown: "mm:ss", "00:00" at 0 and below, "hh:mm:ss" at 1 hour and more | logic_test (0, -5000, 59 999, 60 000, 3 599 000, 3 600 000) |
| nextPollDelay at 0 -> 3000, 119 999 -> 3000, 120 000 -> 10000 | logic_test |
| Mock demo-ok: verified on the 3rd status check after a claim | api_mock_test |
| Mock demo-mismatch: mismatch on the 2nd status check | api_mock_test |
| Mock USED1234 -> alreadyUsed | api_mock_test |
| Attempts 5 -> 0, then noAttemptsLeft | api_mock_test (accepted and alreadyUsed both count) |
| Mock demo-expired -> expired (session and submit) | api_mock_test |
| Unknown token -> notFound (getSession, getStatus, submitClaim) | api_mock_test |
| Mock demo-slow: deviceOnline false; after a claim it stays pending | api_mock_test (many status checks, still pending) |
| Mock demo-paid: already verified with TrxID 9K48X7Z2 | api_mock_test |
| Mock sessions: "নমুনা স্টোর", "#1045", 125000, expiry 30 min after load, 4 wallets (bkash merchant, nagad merchant, rocket agent, upay merchant), attemptsLeft 5 | api_mock_test |
| logic.js and api.mock.js are plain ES modules Deno can import | the tests import them directly; search: no remote imports in pay_page |
| (cut line, D20) No innerHTML / outerHTML / insertAdjacentHTML / document.write in pay_page | search: `grep -rnE "innerHTML\|outerHTML\|insertAdjacentHTML\|document\.write" pay_page` prints nothing |

Other rules (not in the visible criteria, checked too)

| Rule | Check |
|---|---|
| No other HTML or code sinks | search: no `createContextualFragment`, `DOMParser`, `srcdoc`, `eval(`, `new Function`, string `setTimeout(`/`setInterval(`, `on...=` attributes in HTML or set from JS |
| CSP meta tag exactly as the spec, with the spec 13 comment | review index.html |
| No inline script/style (CSP would block them) | search: no `<script>` without src, no `style=`, no `setAttribute('style'` |
| No third-party requests, cookies, localStorage, sessionStorage | search: no `http` URLs except comments/config, no `document.cookie`, `localStorage`, `sessionStorage` |
| Page never asks for PIN, OTP or password | search: no input other than the TrxID input; review of texts |
| HTML + CSS + JS under 60 KB | `cat pay_page/*.html pay_page/*.css pay_page/*.js \| wc -c` < 61440 (fonts and tests not counted) |
| Money is whole poisha; no fractional values | logic_test: formatPoisha(1.5) and formatPoisha(-1) throw; search: no parseFloat / toFixed in pay_page |
| Every screen text matches the spec (rules 1-8, footer, warning line) | manual walk through all URLs in section 4, against a checklist of the spec's Bangla strings; review of STRINGS |
| Files are UTF-8 without BOM | search (as in spec 05) |
| URL gives only the token | review: app.js reads only `t` from location.search |
| returnUrl only https (or localhost) | logic_test for isSafeReturnUrl ("javascript:..." refused) |
| 10-second timeout -> network message, form stays filled | logic_test for withTimeout + manual SLOW1234 (D21) |
| Network error -> "ইন্টারনেট সংযোগ দেখুন", form stays filled | manual NETERR12 (D21) |
| rateLimited text | manual RATE1234 (D21) |
| Invalid TrxID -> message and nothing sent | manual: "123" -> message; mock call count unchanged (dev console) |
| Double tap -> one request | review: busy flag set before the first await; manual fast double tap |
| Operator tabs only for session operators; one operator -> no tabs | manual: demo-ok shows 4 tabs; demo-one shows none (section 5, item 9) |
| Copy wallet; blocked clipboard toast | manual on http://127.0.0.1 (copy works) and on the LAN address (clipboard blocked -> fallback toast) |
| Countdown amber under 5 minutes; at 0 re-checks then expired | manual: open demo-ok and wait, or temporarily shorten expiry in the mock (not committed) |
| Pending: messages before/after 2 minutes; offline note on demo-slow; "বদলান" link hidden at 0 attempts | manual URLs in section 4 |
| Polling pauses when the tab is hidden | manual: devtools Network tab while switching tabs |
| Mismatch keeps polling every 10 s | manual: demo-mismatch, devtools |
| Reopening shows the current status (demo-paid -> verified) | manual URL |
| 320 px: no sideways overflow; buttons >= 44 px; body >= 15 px | manual: devtools device toolbar at 320 px + review of styles.css |
| Chrome for Android and Samsung Internet | you, on a phone (section 4) |

## 4. Serving locally

From D:\BDPay (Python is already installed; nothing to download):
```
python -c "import http.server as h, functools as f; H=h.SimpleHTTPRequestHandler; H.extensions_map.update({'.js':'text/javascript','.css':'text/css'}); h.ThreadingHTTPServer(('127.0.0.1',8080), f.partial(H, directory='pay_page')).serve_forever()"
```
(The MIME line matters: on Windows, Python can serve .js as text/plain from the registry, and browsers refuse to run
a module script with that type. It binds to 127.0.0.1 only, so nothing on your network can reach it.)

Test URLs:
- http://127.0.0.1:8080/index.html?t=demo-ok - pay, then verified after ~9 s (3rd poll)
- http://127.0.0.1:8080/index.html?t=demo-mismatch - pay, then mismatch after ~6 s
- http://127.0.0.1:8080/index.html?t=demo-slow - pay, stays pending, amber "offline" note
- http://127.0.0.1:8080/index.html?t=demo-expired - expired screen
- http://127.0.0.1:8080/index.html?t=demo-paid - straight to verified (TrxID 9K48X7Z2)
- http://127.0.0.1:8080/index.html?t=nothing - not found
- http://127.0.0.1:8080/index.html - not found (no token)
TrxIDs to try on any open screen: USED1234 (already used), "123" (invalid, nothing sent), and with D21:
RATE1234, NETERR12, SLOW1234.

Phone test (optional, only if you want it): replace 127.0.0.1 with 0.0.0.0 in the command and open
http://<PC's LAN IP>:8080/... on the phone. That exposes the page to your local network while it runs; the clipboard
copy will show the "blocked" toast there because the page is not https (that is the blocked-clipboard check).

## 5. Unclear or wrong in the spec

1. **Spec is cut off** -> D20.
2. **Fonts missing** -> D19. **Deno missing** -> D18.
3. **Mismatch polling contradicts itself.** Rule 5 says polling stops at mismatch; rule 7 says it continues every 10 s.
   Plan: rule 7 wins on the mismatch screen (every 10 s, paused while hidden) until verified; it keeps going after the
   order's expiry, because a manual approval can come later.
4. **Countdown reaching 0 when the status is mismatch.** Rule 8 says "shows this screen if still not verified". Plan:
   after the last check, show the screen for the returned status: verified -> verified, mismatch -> mismatch
   (with its 10 s polling), open/pending/expired -> expired.
5. **"Reopening shows the current status" vs the mock.** The mock keeps its state in memory, so reloading a demo-ok page
   after a claim starts from "open" again (the page may not store the TrxID locally). demo-paid shows the rule; the
   real API (spec 13) keeps the state on the server.
6. **"Under 2 minutes" after a reload.** Session has no submittedAt, so after reopening a pending link the page can't
   know how long ago the claim was made. Plan: count from when this page saw the submit (or the load). Proper fix in
   spec 13: add submittedAt to Session.
7. **Countdown rounding.** Plan: whole seconds rounded up, so 0.4 s left shows "00:01" and "00:00" only when time is up.
8. **formatPoisha "same rules as the app"** includes: negative throws (RangeError), comma groups, always 2 decimals.
9. **Single-operator session** has no mock token -> D24.
10. **CSP `connect-src` with "the API origin from config.js"**: there is no origin yet. Plan: `connect-src 'self'` and
    an HTML comment to add the origin in spec 13. Also: frame-ancestors (clickjacking protection) is ignored in a meta
    tag; spec 13 hosting should send it as an HTTP header.
11. **style-src 'self'** blocks style attributes, so app.js uses classes only (no `el.setAttribute('style', ...)`).
12. **CLAUDE.md vs this spec.** CLAUDE.md puts the "customer TrxID page" in apps/dashboard (Flutter web) and wants all
    text from ARB files. This spec (current step, it wins) makes it a plain static page in pay_page/. Plan: all UI text
    in one STRINGS object at the top of app.js (one place to edit); steps text in instructions.js. CLAUDE.md should be
    updated.
13. **CLAUDE.md claim status "rejected"** is missing from Session.status -> D22.
14. **Agent wallets and fees** -> D23.
15. **PIN wording.** The steps must say to enter the PIN in the operator's own app; the footer says BDPay never asks for
    it. Plan: steps say "{operator} অ্যাপে আপনার পিন দিয়ে নিশ্চিত করুন" - the page itself has no PIN field.
16. **Reference file name.** reference/bdpay-sms-verifier-v2.html does not exist; the root "BDPay SMS Verifier.html" is used.
17. **"৯কে৪৮…" example** is only an aside; the real example is Rocket "২৪০১০২০০১২৩" -> "24010200123".

## 6. Where outside text enters the page

| Source | Where it goes | Guard |
|---|---|---|
| merchantName, orderRef, walletNumber, submittedTrxId, amounts, times | screen text | textContent only; numbers go through formatPoisha / formatDhakaTime |
| operator, accountType | class name, tab label, step list | must be one of the 4 operators / 2 account types, else that wallet is skipped |
| instructions.js steps (with wallet, amount, orderRef filled in) | step list | plain strings, set with textContent |
| returnUrl | "দোকানে ফিরে যান" (location.assign) | isSafeReturnUrl: only https:, or http://localhost / 127.0.0.1; otherwise the button is hidden |
| The TrxID the customer types | input value, then the API | input.value (text), normalized; shown later with textContent |
| URL token `t` | only passed to the API | never written into the page |
| Errors / exceptions | never shown | the screens show fixed STRINGS only |
| Clipboard | writeText(walletNumber) | text only |
Second wall: the CSP has no 'unsafe-inline' or 'unsafe-eval', so even an HTML mistake could not run inline script
(D25 adds Trusted Types on top).

## 7. Review log

Review 1 against spec 07 and CLAUDE.md:
- Outside Scope: no framework, npm or build step; nothing downloaded. Found: the Deno tests could have used jsr:@std/assert
  (a download) -> now node:assert/strict (built in). Extra mock behaviour (D21 triggers, demo-one) and the extra CSP
  line are decisions (D21, D24, D25), not plan defaults; D22 option A (a new screen) is also only with your yes.
  The Python serve command is a local tool, not part of the page.
- Server/user text as HTML: textContent everywhere was already planned. Added: attribute values only from fixed code;
  operator/accountType whitelisted; returnUrl checked against javascript: and other schemes; error objects never
  shown; the URL token never written into the page; a wider search (DOMParser, createContextualFragment, srcdoc,
  eval, new Function, string timers, on* attributes); section 6 lists every entry point.
- Criteria: the visible criteria all had checks. Added rows for demo-slow, demo-paid, the mock session data and
  expiry, "Deno can import them", the screen texts, the exact size command, BOM.
- CLAUDE.md: money as whole poisha made explicit (safe integers, no parseFloat/toFixed); "the server decides paid"
  made explicit (verified only from the server's status); "open" is a page state, not a claim status (no claim yet);
  "rejected" is D22; Flutter/ARB vs this spec noted in section 5, item 12 (spec wins).

## 8. Execution log (2026-10-29)

- Deno 2.9.8 installed with winget (approved, D18). Tests import only node:assert/strict; running them downloaded nothing.
- No fonts/ folder (D19 = B): the CSS names "Noto Sans Bengali" first and falls back to the phone's font.
- D21 (RATE1234, NETERR12, SLOW1234), D23 (agent fee line), D24 (demo-one) and D25 (Trusted Types in the CSP) built;
  D22 left to spec 13; D20 still open (the visible criteria were used).
- Found while checking: the CSP comment in index.html contained the word "innerHTML", which would fail the spec's
  literal search -> reworded. A `<meta name="referrer">` line was added and then removed again (not in the spec).
- Mock returnUrl is https://example.com/orders/1045 (a reserved test domain).
- Results: deno test 26 passed; deno lint clean; deno check clean; HTML+CSS+JS 36.9 KB; local server serves every file
  (JS as text/javascript).
