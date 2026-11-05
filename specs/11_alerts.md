# 11 Alerts

Purpose
Tell the merchant quickly, by email, when payments cannot be verified: the phone is silent or has
stopped watching SMS, no phone is set up, Shopify needs reconnecting, a Shopify order could not be
marked paid, or payments are waiting for their review. One email when a problem starts, reminders
while it lasts, and a "fixed" email for the phone problem.

Scope
- Edge Functions in supabase/functions/: alerts-check (scheduled every 5 minutes) and alerts-list (for the app).
- Shared code in supabase/functions/_shared/: alert_rules.ts (pure decisions), alert_messages.ts
  (Bangla email texts), mailer.ts (Mailer interface + FakeMailer), and Store additions in Contract.
- Changes to earlier backend code, and only these:
  - device-heartbeat (spec 08) also saves smsPermission, monitoring and batteryOptimizationOff on the device.
  - shopify-sync / ShopifyNotifier (spec 10): when an OrderSync becomes failed, raise a syncFailed event alert.
- Deno tests in supabase/functions/tests/.
- Not in scope: choosing and setting up the real email provider (spec 15), SMS or push alerts,
  alert settings for the merchant, showing alerts in the app (spec 13), SQL (spec 12).

Contract
Alert record: id, merchantId, kind, status (open | resolved), openedAt, lastSentAt (or null),
sendCount, resolvedAt (or null), details (small JSON, never TrxID, amounts, payer numbers or SMS text).
Kinds (wire names = future SQL CHECK values):
  condition kinds: phoneSilent, monitoringOff, noActiveDevice, shopifyReconnect, reviewWaiting
  event kind: syncFailed

Device additions (spec 08 record): lastSmsPermission, lastMonitoring, lastBatteryOk (booleans or null).

Store additions (spec 12 builds tables from these):
  listAlertInputs(now) -> AlertInput[] for every merchant that has an active device or an active store:
    {merchantId, activeDeviceCount, newestDeviceSeenAt (or null), anyDeviceProblem (an active device
     seen in the last 15 minutes whose last heartbeat had smsPermission false or monitoring false),
     storeActive, storeConnectedAt (or null), storeReconnectNeeded, pendingClaimCount,
     reviewWaitingCount (mismatch claims older than 60 minutes)}
  listOpenAlerts(merchantId) -> Alert[]
  openAlert(merchantId, kind, details) -> Alert   (at most one open alert per merchant + condition kind)
  markAlertSent(id, sentAt) -> void (sendCount + 1)
  resolveAlert(id, resolvedAt) -> void
  createEventAlert(merchantId, kind, details) -> Alert
  listUnsentEventAlerts(limit) -> Alert[]
  getMerchantContact(merchantId) -> {email, businessName}

Mailer: send({to, subject, text}) -> "sent" | "failed". FakeMailer keeps sent mails in memory for tests.

alert_rules.ts (pure):
  decide(input, openAlerts, now) -> list of actions: {open, kind} | {remind, alertId} | {resolve, alertId, sendFixed}
Condition rules:
  phoneSilent: activeDeviceCount > 0 and (newestDeviceSeenAt older than 15 minutes,
    or older than 5 minutes while pendingClaimCount > 0). Clears when seen within the last 5 minutes.
  monitoringOff: anyDeviceProblem is true. Clears when false.
    (phoneSilent wins: monitoringOff does not open while phoneSilent is open.)
  noActiveDevice: storeActive and activeDeviceCount = 0 and storeConnectedAt older than 30 minutes.
    Clears when a device is active.
  shopifyReconnect: storeReconnectNeeded. Clears when false.
  reviewWaiting: reviewWaitingCount > 0. Clears when 0.
Reminders, while still open:
  phoneSilent every 2 hours, at most 6 emails per open alert.
  monitoringOff and noActiveDevice every 6 hours, at most 4.
  shopifyReconnect and reviewWaiting every 24 hours, at most 7.
Fixed email: only for phoneSilent, and only if at least one email was sent for it.
An alert whose email failed (lastSentAt null) is tried again on the next check; it does not count as a reminder.

Function contracts:
1. alerts-check (header X-Cron-Secret = CRON_SECRET, else 401)
   POST {} -> for each AlertInput: decide, apply (open/resolve in store), send emails; then send unsent
   event alerts (up to 50). -> 200 {ok: true, opened, reminded, resolved, eventsSent, mailFailed}.
   One merchant's error never stops the others.
2. alerts-list (Supabase user token; owner of a merchant)
   GET -> 200 {ok: true, alerts: [{id, kind, openedAt, title, hint}]} with open condition alerts and event
   alerts from the last 7 days, newest first. title and hint are the Bangla texts below.

Emails (alert_messages.ts, plain text, Bangla; the subject starts with "BDPay: "; the text starts with
"{businessName}," and ends with "— BDPay"):
  phoneSilent: "যাচাই ফোন অফলাইন — পেমেন্ট নিশ্চিত হচ্ছে না".
    Text says the phone has not contacted BDPay since {time in Asia/Dhaka}; if pendingClaimCount > 0,
    "{n} জন গ্রাহক পেমেন্ট নিশ্চিতের অপেক্ষায় আছেন"; steps: ফোন চালু ও চার্জে রাখুন, ইন্টারনেট দেখুন,
    BDPay অ্যাপ খুলুন.
  phoneSilent fixed: "যাচাই ফোন আবার সংযুক্ত হয়েছে".
  monitoringOff: "ফোনে এসএমএস দেখা বন্ধ আছে". Steps: অ্যাপ খুলে ডিভাইস স্বাস্থ্য দেখুন, এসএমএস অনুমতি ও মনিটরিং চালু করুন.
  noActiveDevice: "কোনো যাচাই ফোন যুক্ত নেই". Steps: যে ফোনে bKash/Nagad সিম আছে সেই ফোনে BDPay অ্যাপে লগইন করুন.
  shopifyReconnect: "Shopify আবার যুক্ত করুন". Steps: অ্যাপ > সেটিংস > Shopify স্টোর > আবার যুক্ত করুন.
  reviewWaiting: "{n} টি পেমেন্ট আপনার রিভিউয়ের অপেক্ষায়". Steps: অ্যাপ > লেনদেন > "টাকা মেলেনি" দেখুন.
  syncFailed: "Shopify-তে অর্ডার {orderRef} 'Paid' করা যায়নি". Text: the payment is verified in BDPay;
    mark the order paid by hand in Shopify admin. (details holds only orderRef.)
The app titles/hints for alerts-list are the subject line and the first step.

Functional rules
- Emails never contain TrxID, amounts, payer numbers, SMS text, tokens or links with tokens.
- Times in emails are shown in Asia/Dhaka.
- If the merchant has no email address, skip sending and leave lastSentAt null (no crash).

Edge cases
- Phone silent 16 minutes, no pending claims -> phoneSilent opens, 1 email.
- Phone silent 6 minutes with 2 pending claims -> phoneSilent opens early.
- Phone back after 3 hours -> resolved and one "fixed" email.
- Phone flaps (silent 16 min, back, silent again 20 min later) -> a new alert each time; no duplicate open alerts.
- A merchant with 2 phones, one silent and one fine -> no phoneSilent (newest seen is recent).
- Brand-new merchant with Shopify connected 10 minutes ago and no phone -> nothing yet; at 31 minutes noActiveDevice.
- Mail provider down -> mailFailed counted, alert stays open, retried next run.
- syncFailed raised twice for the same OrderSync -> one event alert (details orderRef + syncId, unique).

Non-functional rules
- alert_rules.ts is pure and fully unit-tested with a fixed clock.
- Never log email addresses or email bodies. Log merchantId, kind and action only.
- deno check, deno lint and deno fmt --check pass.

Acceptance criteria
- deno test supabase/functions/tests passes (specs 08-10 still pass), covering:
  - every edge case above;
  - reminder timing and limits for each kind (phoneSilent 7th reminder not sent);
  - monitoringOff does not open while phoneSilent is open;
  - fixed email only after a sent phoneSilent email;
  - heartbeat saves the three health fields;
  - shopify-sync raises one syncFailed alert when an OrderSync becomes failed;
  - alerts-check wrong secret 401; one merchant throwing does not stop the next;
  - alerts-list returns only the caller's alerts, newest first, with Bangla title and hint;
  - a test scans every generated email and fails if it contains a TrxID pattern, a "৳" amount or "01" phone number.
- deno check, deno lint and deno fmt --check pass.

Assumptions
- Specs 08, 09 and 10 are done.
- The app sends a heartbeat every 5 minutes from spec 13.
- The real Mailer (provider, sender address) is set up in spec 15; until then FakeMailer is used in local runs.
