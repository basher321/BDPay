# 07a Pay page: rejected screen

Purpose
When the merchant rejects a payment by hand (spec 03), the customer must see that clearly.

Scope
- Session status gets one more value: rejected.
- A rejected screen in pay_page/app.js and a mock token demo-rejected in api.mock.js.
- No other change.

Functional rules
- Rejected screen: red ✕, "পেমেন্ট গ্রহণ করা হয়নি", "দোকান এই পেমেন্টটি গ্রহণ করেনি। TrxID {trx} সহ দোকানে যোগাযোগ করুন।",
  and "দোকানে ফিরে যান" -> returnUrl. No countdown. Polling stops.
- The mismatch screen's polling (every 10 s) moves to this screen when status becomes rejected.
- demo-rejected: a claim with TrxID 8H22K9P1 is already submitted and the status is rejected.
- When status is pending, the countdown may be longer than 1 hour (hh:mm:ss), because the server
  keeps matching for 24 hours after a TrxID is submitted.

Acceptance criteria
- deno test pay_page/tests passes with a new test: demo-rejected returns status rejected.
- ?t=demo-rejected shows the rejected screen; no innerHTML is added; size still under 60 KB.
