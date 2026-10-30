-- BDPay spec 14: read-only queries for Dashboard > SQL Editor on staging. SELECT only.
-- They show counts, ids, statuses, reasons and times only - never SMS text, senders, TrxIDs, payer or wallet
-- numbers, tokens, keys, notes, alert details or emails (plan 14 D200).
-- Column names follow spec 12. Times are shown in Asia/Dhaka.

-- 1a. Verification time per payment, last 7 days (seconds).
--     sms_to_match: SMS received on the phone -> match; sms_server_to_match: SMS reached the server -> match;
--     claim_to_match: customer entered the TrxID -> match. The bigger of the last two is the customer's wait.
select
  m.id as match_id,
  m.method,
  m.created_at at time zone 'Asia/Dhaka' as matched_at_dhaka,
  round(extract(epoch from (m.created_at - s.received_at))::numeric, 1) as sms_to_match_s,
  round(extract(epoch from (m.created_at - s.server_received_at))::numeric, 1) as sms_server_to_match_s,
  round(extract(epoch from (m.created_at - c.created_at))::numeric, 1) as claim_to_match_s
from public.matches m
join public.sms_messages s on s.id = m.sms_id
join public.payment_claims c on c.id = m.claim_id
where m.created_at > now() - interval '7 days'
order by m.created_at desc;

-- 1b. Median of the same, automatic matches only (manual approvals wait for a person), last 7 days.
select
  count(*) as payments,
  round(percentile_cont(0.5) within group (order by extract(epoch from (m.created_at - s.server_received_at)))::numeric, 1)
    as median_sms_server_to_match_s,
  round(percentile_cont(0.5) within group (order by extract(epoch from (m.created_at - c.created_at)))::numeric, 1)
    as median_claim_to_match_s,
  round(percentile_cont(0.5) within group (order by greatest(
    extract(epoch from (m.created_at - s.server_received_at)),
    extract(epoch from (m.created_at - c.created_at))))::numeric, 1)
    as median_customer_wait_s
from public.matches m
join public.sms_messages s on s.id = m.sms_id
join public.payment_claims c on c.id = m.claim_id
where m.method = 'auto'
  and m.created_at > now() - interval '7 days';

-- 2. Heartbeat gaps per device, last 48 hours: the 10 biggest per device.
--    History: devices keeps only last_seen_at, but every device-heartbeat writes an audit_log row
--    (action 'device.heartbeat'), so the gaps come from audit_log. Only times and ids are read.
with beats as (
  select
    a.actor_id as device_id,
    a.created_at,
    lag(a.created_at) over (partition by a.actor_id order by a.created_at) as previous_at
  from public.audit_log a
  where a.action = 'device.heartbeat'
    and a.actor_type = 'device'
    and a.created_at > now() - interval '48 hours'
),
gaps as (
  select
    device_id,
    previous_at,
    created_at,
    round(extract(epoch from (created_at - previous_at))::numeric / 60, 1) as gap_min,
    row_number() over (partition by device_id order by created_at - previous_at desc) as rank_in_device
  from beats
  where previous_at is not null
)
select
  device_id,
  previous_at at time zone 'Asia/Dhaka' as from_dhaka,
  created_at at time zone 'Asia/Dhaka' as to_dhaka,
  gap_min
from gaps
where rank_in_device <= 10
order by device_id, gap_min desc;

-- 2b. Gaps over 15 minutes (the phoneSilent limit), last 48 hours, per device.
with beats as (
  select
    a.actor_id as device_id,
    a.created_at - lag(a.created_at) over (partition by a.actor_id order by a.created_at) as gap
  from public.audit_log a
  where a.action = 'device.heartbeat'
    and a.actor_type = 'device'
    and a.created_at > now() - interval '48 hours'
)
select device_id, count(*) as gaps_over_15_min, round(max(extract(epoch from gap))::numeric / 60, 1) as biggest_gap_min
from beats
where gap > interval '15 minutes'
group by device_id
order by gaps_over_15_min desc;

-- 3. Rejected SMS by reason, last 7 days (counts only).
select s.operator, s.reject_reason, count(*) as rejected
from public.sms_messages s
where s.status = 'rejected'
  and s.server_received_at > now() - interval '7 days'
group by s.operator, s.reject_reason
order by rejected desc;

-- 4. Order syncs not done.
select
  o.id as sync_id,
  o.session_id,
  o.status,
  o.attempts,
  o.next_attempt_at at time zone 'Asia/Dhaka' as next_attempt_dhaka,
  o.last_error,
  o.created_at at time zone 'Asia/Dhaka' as created_dhaka
from public.order_syncs o
where o.status <> 'done'
order by o.created_at desc;

-- 5. Open alerts, and phoneSilent alerts opened in the last 24 hours (test P).
select
  al.id as alert_id,
  al.kind,
  al.status,
  al.opened_at at time zone 'Asia/Dhaka' as opened_dhaka,
  al.send_count,
  al.last_sent_at at time zone 'Asia/Dhaka' as last_sent_dhaka
from public.alerts al
where al.status = 'open'
order by al.opened_at desc;

select count(*) as phone_silent_opened_24h
from public.alerts al
where al.kind = 'phoneSilent'
  and al.opened_at > now() - interval '24 hours';
