# 07 Customer pay page

Purpose
Give the customer one simple page after a Shopify order: see who they are paying and the
exact amount, pay from their bKash / Nagad / Rocket / Upay app, enter the TrxID, and see
the result update on its own. This page is where the claim comes from, so it is the other
half of every match. It follows the style of reference/bdpay-sms-verifier-v2.html
(dark theme, emerald, cards, Bangla).

Scope
- A static web page in pay_page/: index.html, styles.css, app.js (screens and events),
  logic.js (pure functions), api.js (the API interface), api.mock.js (mock server),
  instructions.js (payment steps per operator and account type), config.js (which API to use).
- Self-hosted Noto Sans Bengali: copy the font files from app/assets/fonts to pay_page/fonts.
- Deno unit tests in pay_page/tests/ for logic.js and api.mock.js.
- No framework, no npm, no build step, no third-party scripts, styles, fonts or analytics.
- Not in scope: the real API (spec 13), the Shopify link to this page (spec 10), English,
  card or other payment methods.

Contract
URL: index.html?t=TOKEN. The page never takes amount, wallet or order data from the URL.

api.js exposes three async functions. config.js chooses the mock (api.mock.js) or, later, the real API.
- getSession(token) -> Session or {error: "notFound"}
- submitClaim(token, operator, trxId) -> {result, session}
  result: accepted | invalidFormat | alreadyUsed | noAttemptsLeft | expired | notFound | rateLimited
- getStatus(token) -> Session or {error: "notFound"}

Session:
  token, merchantName, orderRef, amountPoisha (integer), expiresAt (ISO UTC),
  status: open | pending | verified | mismatch | expired,
  operators: [{operator: bkash|nagad|rocket|upay, walletNumber, accountType: merchant|agent}],
  attemptsLeft (integer, starts at 5), returnUrl, deviceOnline (bool),
  submittedOperator (or null), submittedTrxId (or null), verifiedAt (or null)

logic.js (pure, no DOM):
- formatPoisha(int) -> "৳ 1,250.00" (same rules as the app).
- normalizeTrxId(text): Bangla digits -> English, remove spaces, upper case.
- isValidTrxId(operator, trx): bkash/nagad/upay 8-12 letters or digits; rocket 8-14 digits only.
- formatCountdown(msLeft): "mm:ss", "00:00" when 0 or less, "hh:mm:ss" when 1 hour or more.
- nextPollDelay(msSinceSubmit): 3000 for the first 2 minutes, then 10000.

Mock tokens (api.mock.js, merchant "নমুনা স্টোর", order "#1045", amount 125000,
expiry 30 minutes after page load, wallets for all 4 operators: bkash merchant, nagad merchant,
rocket agent, upay merchant):
- demo-ok: after a claim, status becomes verified on the 3rd status check.
- demo-mismatch: after a claim, status becomes mismatch on the 2nd status check.
- demo-slow: deviceOnline false; after a claim it stays pending.
- demo-expired: expiresAt is already in the past, status expired.
- demo-paid: already verified (TrxID 9K48X7Z2).
- any other token: notFound.
- TrxID USED1234 -> alreadyUsed. Every accepted or alreadyUsed claim lowers attemptsLeft by 1;
  at 0 -> noAttemptsLeft.
Mark the file "MOCK - replaced by the real API in spec 13".

instructions.js: for each operator and account type, 4-5 short Bangla steps that include the
wallet number, the exact amount and "রেফারেন্স: {orderRef}". merchant -> "Make Payment" / "পেমেন্ট";
agent -> "Cash Out" / "ক্যাশ আউট". Mark every entry "SAMPLE - check the wording in each operator's app".

Functional rules
1. Loading: logo, "BDPay" and a spinner "লোড হচ্ছে…". Then one of the screens below by status.
2. Not found: "এই পেমেন্ট লিংক পাওয়া যায়নি" and "দোকান থেকে পাওয়া লিংকটি আবার খুলুন".
3. Open (pay) screen, top to bottom:
   a. Merchant card: merchantName (big), "অর্ডার {orderRef}", the amount (32, emerald) and
      "সময় বাকি {countdown}". Under 5 minutes the countdown turns amber.
   b. Warning line: "ঠিক {amount} পাঠান — কম বা বেশি পাঠালে যাচাই হবে না।"
   c. Operator tabs: only the operators in session.operators, in brand text colors, like the
      app's chips. The first one is selected.
   d. Steps card for the selected operator: the wallet number (large, with a "⧉ কপি" button,
      toast "কপি হয়েছে") and the numbered steps from instructions.js.
   e. TrxID form: label "পেমেন্টের পর পাওয়া TrxID দিন", one input (autocomplete off,
      autocapitalize characters), button "যাচাই করুন". Under the button: "{attemptsLeft} বার চেষ্টা বাকি".
   f. Footer: "BDPay দিয়ে নিরাপদ যাচাই • আপনার পিন কখনো চাওয়া হবে না".
4. Submitting
   - The TrxID is normalized, then checked with isValidTrxId before sending. Invalid ->
     "TrxID সঠিক নয় — এসএমএস থেকে আবার দেখুন" and nothing is sent.
   - The button shows "পাঠানো হচ্ছে…" and is disabled until the answer comes.
   - Results: accepted -> pending screen; invalidFormat -> same message as above;
     alreadyUsed -> "এই TrxID আগেই ব্যবহার হয়েছে"; noAttemptsLeft -> "আর চেষ্টা করা যাবে না —
     দোকানে যোগাযোগ করুন"; expired -> expired screen; notFound -> not found screen;
     rateLimited -> "অনেকবার চেষ্টা হয়েছে — একটু পরে আবার চেষ্টা করুন".
   - A network error -> "ইন্টারনেট সংযোগ দেখুন" and the form stays filled.
5. Pending screen
   - Spinner, "পেমেন্ট যাচাই হচ্ছে…", the operator and TrxID entered, the amount, the countdown.
   - Under 2 minutes: "সাধারণত ১ মিনিটের মধ্যে নিশ্চিত হয়"; after 2 minutes: "এখনো নিশ্চিত হয়নি —
     এই পেজ খোলা রাখুন বা পরে এই লিংকে ফিরে আসুন".
   - If deviceOnline is false: an amber note "দোকানের যাচাই ফোন এখন অফলাইন — নিশ্চিত হতে দেরি হতে পারে".
   - A link "TrxID ভুল দিয়েছেন? বদলান" returns to the open screen with the operator and TrxID
     prefilled (a new submit uses one attempt). Hidden when attemptsLeft is 0.
   - Polling: getStatus after nextPollDelay; paused while the browser tab is hidden and resumed
     when visible; stopped at verified, mismatch or expired.
6. Verified screen: big ✓ (emerald), "পেমেন্ট নিশ্চিত হয়েছে", amount, operator + TrxID, order ref,
   time (Asia/Dhaka), and the primary button "দোকানে ফিরে যান" -> returnUrl.
7. Mismatch screen: amber "!", "টাকার পরিমাণ মেলেনি", "দোকান আপনার পেমেন্ট দেখে নিশ্চিত করবে।
   প্রয়োজনে দোকানে এই TrxID জানান: {trx}", and "দোকানে ফিরে যান". Polling continues every 10 s,
   because the merchant may approve it by hand (spec 03) -> then the verified screen shows.
8. Expired screen: "সময় শেষ", "এই অর্ডারের পেমেন্টের সময় পার হয়ে গেছে।", and "টাকা পাঠিয়ে থাকলে
   TrxID সহ দোকানে যোগাযোগ করুন।" plus "দোকানে ফিরে যান". When the countdown reaches 0 on the
   open or pending screen, the page checks the status once more, then shows this screen if still not verified.
9. Reopening the link at any time shows the screen for the current status (for example demo-paid
   opens straight on the verified screen).

Security rules
- All text from the server or the user is put into the page with textContent only.
  innerHTML, outerHTML, insertAdjacentHTML and document.write are not used anywhere.
- index.html has a Content-Security-Policy meta tag: default-src 'self'; img-src 'self' data:;
  style-src 'self'; script-src 'self'; connect-src 'self' plus the API origin from config.js
  (written in the tag by hand, with a comment to update it in spec 13).
- No cookies, no localStorage of the TrxID, no third-party requests.
- The page never asks for a PIN, OTP or password.

Edge cases
- Bangla digits in the TrxID ("৯কে৪৮…" is not possible, but "২৪০১০২০০১২৩" for Rocket is) -> converted.
- A TrxID with spaces " 9k48 x7z2 " -> "9K48X7Z2".
- Session with one operator -> no tabs, just that operator's card.
- Slow network: every request has a 10-second timeout and shows the network error message.
- Double tap on "যাচাই করুন" -> one request.
- Screen width 320 px -> nothing overflows sideways.
- Wallet copy when the clipboard is blocked -> toast "কপি করা যায়নি — নম্বরটি দেখে লিখে নিন".

Non-functional rules
- Total size of HTML + CSS + JS under 60 KB (fonts not counted).
- Works on Chrome for Android (last 3 years) and the default Samsung browser.
- Buttons at least 44 px high, body text at least 15 px (customers read this outdoors on phones).
- logic.js and api.mock.js are plain ES modules that Deno can import for tests.

Acceptance criteria
- deno test pay_page/tests passes, covering: every formatPoisha, normalizeTrxId, isValidTrxId and
  formatCountdown example in this spec; nextPollDelay at 0, 119999 and 120000 ms; the mock flows
  demo-ok (verified on 3rd status), demo-mismatch, USED1234 -> alreadyUsed, attempts going 5 -> 0
  -> noAttemptsLeft, demo-expired, unknown token -> notFound.
- A search of pay_page shows no innerHTML, outerHTML,
