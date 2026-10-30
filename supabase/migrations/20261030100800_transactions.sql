-- Spec 12 all-or-nothing functions behind the Store (spec 08/09/10). Each runs in one transaction; a failed check
-- returns a conflict and changes nothing. Callable by the service role only (the Edge Functions).

create or replace function public.insert_sms(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.sms_messages;
  v_created boolean := true;
begin
  insert into public.sms_messages (
    merchant_id, device_id, wallet_id, sender, body, received_at, server_received_at, sim_slot, dedupe_hash,
    operator, trx_id, amount_poisha, payer_number, status, reject_reason, parser_version)
  values (
    (p ->> 'merchant_id')::uuid, (p ->> 'device_id')::uuid, nullif(p ->> 'wallet_id', '')::uuid, p ->> 'sender',
    p ->> 'body', (p ->> 'received_at')::timestamptz, coalesce((p ->> 'server_received_at')::timestamptz, now()),
    p ->> 'sim_slot', p ->> 'dedupe_hash', p ->> 'operator', p ->> 'trx_id', (p ->> 'amount_poisha')::bigint,
    p ->> 'payer_number', p ->> 'status', p ->> 'reject_reason', (p ->> 'parser_version')::int)
  on conflict (merchant_id, dedupe_hash) do nothing
  returning * into v;
  if v.id is null then
    v_created := false;
    select * into v from public.sms_messages
    where merchant_id = (p ->> 'merchant_id')::uuid and dedupe_hash = p ->> 'dedupe_hash';
  end if;
  return jsonb_build_object('sms', to_jsonb(v), 'created', v_created);
end;
$$;

create or replace function public.spend_attempt(p_session_id uuid)
returns int
language sql
security definer
set search_path = ''
as $$
  update public.payment_sessions set attempts_left = greatest(attempts_left - 1, 0)
  where id = p_session_id
  returning attempts_left;
$$;

create or replace function public.submit_claim(p_session_id uuid, p_operator text, p_trx_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.payment_sessions;
  c public.payment_claims;
  v_trx text := upper(btrim(p_trx_id));
begin
  select * into s from public.payment_sessions where id = p_session_id for update;
  if s.id is null or not (s.status = 'pending' or (s.status = 'open' and now() <= s.submit_deadline)) then
    return jsonb_build_object('conflict', 'closed');
  end if;
  if s.attempts_left <= 0 then
    return jsonb_build_object('conflict', 'noAttemptsLeft');
  end if;
  if exists (
    select 1 from public.payment_claims
    where merchant_id = s.merchant_id and operator = p_operator and trx_id = v_trx
      and status in ('pending', 'verified', 'mismatch')
  ) then
    return jsonb_build_object('conflict', 'alreadyUsed');
  end if;
  begin
    update public.payment_claims set status = 'superseded'
    where id = s.active_claim_id and status = 'pending';
    insert into public.payment_claims (merchant_id, session_id, operator, trx_id, status, match_deadline)
    values (s.merchant_id, s.id, p_operator, v_trx, 'pending', now() + interval '24 hours')
    returning * into c;
    update public.payment_sessions
    set attempts_left = attempts_left - 1, status = 'pending', active_claim_id = c.id
    where id = s.id;
  exception when unique_violation then
    return jsonb_build_object('conflict', 'alreadyUsed');
  end;
  return jsonb_build_object('claim', to_jsonb(c));
end;
$$;

create or replace function public.record_verified(
  p_claim_id uuid, p_sms_id uuid, p_method text, p_user_id uuid, p_note text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.payment_claims;
  m public.sms_messages;
  s public.payment_sessions;
begin
  -- Lock order: claim, then SMS, then session (always the same).
  select * into c from public.payment_claims where id = p_claim_id for update;
  select * into m from public.sms_messages where id = p_sms_id for update;
  if c.id is null or m.id is null then return 'conflict'; end if;
  select * into s from public.payment_sessions where id = c.session_id for update;
  if s.active_claim_id is distinct from c.id then return 'conflict'; end if;
  if p_method = 'auto' then
    if c.status <> 'pending' or s.status <> 'pending' then return 'conflict'; end if;
  elsif p_method = 'manual' then
    if c.status <> 'mismatch' or s.status <> 'mismatch' or c.candidate_sms_id is distinct from m.id then
      return 'conflict';
    end if;
  else
    return 'conflict';
  end if;
  if m.status <> 'unmatched' or m.merchant_id <> c.merchant_id or m.operator is distinct from c.operator
     or m.trx_id is distinct from c.trx_id then
    return 'conflict';
  end if;
  begin
    insert into public.matches (merchant_id, claim_id, sms_id, method, user_id, note)
    values (c.merchant_id, c.id, m.id, p_method, p_user_id, p_note);
  exception when unique_violation then
    return 'conflict';
  end;
  update public.payment_claims set status = 'verified', candidate_sms_id = m.id where id = c.id;
  update public.payment_sessions set status = 'verified', verified_at = now() where id = s.id;
  update public.sms_messages set status = 'matched' where id = m.id;
  return 'ok';
end;
$$;

create or replace function public.record_mismatch(p_claim_id uuid, p_sms_id uuid, p_reason text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.payment_claims;
  m public.sms_messages;
  s public.payment_sessions;
begin
  select * into c from public.payment_claims where id = p_claim_id for update;
  select * into m from public.sms_messages where id = p_sms_id for update;
  if c.id is null or m.id is null then return 'conflict'; end if;
  select * into s from public.payment_sessions where id = c.session_id for update;
  if s.active_claim_id is distinct from c.id or c.status <> 'pending' or s.status <> 'pending'
     or m.status <> 'unmatched' or m.merchant_id <> c.merchant_id then
    return 'conflict';
  end if;
  update public.payment_claims set status = 'mismatch', reason = p_reason, candidate_sms_id = m.id where id = c.id;
  update public.payment_sessions set status = 'mismatch' where id = s.id;
  return 'ok';
end;
$$;

create or replace function public.record_rejected(p_claim_id uuid, p_user_id uuid, p_note text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.payment_claims;
  s public.payment_sessions;
begin
  select * into c from public.payment_claims where id = p_claim_id for update;
  if c.id is null then return 'conflict'; end if;
  select * into s from public.payment_sessions where id = c.session_id for update;
  if s.active_claim_id is distinct from c.id or c.status <> 'mismatch' or s.status <> 'mismatch' then
    return 'conflict';
  end if;
  update public.payment_claims set status = 'rejected' where id = c.id;
  update public.payment_sessions set status = 'rejected' where id = s.id;
  return 'ok';
end;
$$;

create or replace function public.expire_due(p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sessions int := 0;
  v_claims int := 0;
  n int;
begin
  -- Pending claims past their match deadline that are still their session's active claim.
  with due as (
    update public.payment_claims c set status = 'expired'
    from public.payment_sessions s
    where c.status = 'pending' and c.match_deadline < p_now and s.active_claim_id = c.id and s.status = 'pending'
    returning c.session_id
  )
  update public.payment_sessions s set status = 'expired' from due where s.id = due.session_id;
  get diagnostics n = row_count;
  v_claims := n;
  v_sessions := n;
  update public.payment_sessions set status = 'expired'
  where status = 'open' and submit_deadline < p_now;
  get diagnostics n = row_count;
  v_sessions := v_sessions + n;
  return jsonb_build_object('sessions', v_sessions, 'claims', v_claims);
end;
$$;

create or replace function public.hit_rate_limit(p_key text, p_limit int, p_window_seconds int)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  v_count int;
begin
  insert into public.rate_limits (key, window_start, count) values (p_key, v_start, 1)
  on conflict (key, window_start) do update set count = public.rate_limits.count + 1
  returning count into v_count;
  return v_count <= p_limit;
end;
$$;

-- sms-status: each SMS of this merchant with the claim tied to it (its match's claim, else the newest claim that
-- named it as candidate), that claim's session and the match.
create or replace function public.get_sms_results(p_merchant_id uuid, p_sms_ids uuid[])
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'sms', to_jsonb(m),
    'match', to_jsonb(mt),
    'claim', to_jsonb(c),
    'session', to_jsonb(s))
  from public.sms_messages m
  left join public.matches mt on mt.sms_id = m.id
  left join lateral (
    select * from public.payment_claims pc
    where (mt.claim_id is not null and pc.id = mt.claim_id)
       or (mt.claim_id is null and pc.candidate_sms_id = m.id)
    order by pc.created_at desc
    limit 1
  ) c on true
  left join public.payment_sessions s on s.id = c.session_id
  where m.merchant_id = p_merchant_id and m.id = any (p_sms_ids);
$$;

-- Spec 10: single-use, unexpired install state.
create or replace function public.consume_install_state(p_state_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.shopify_install_states;
begin
  update public.shopify_install_states set used_at = now()
  where state_hash = p_state_hash and used_at is null and expires_at > now()
  returning * into v;
  if v.id is null then return null; end if;
  return jsonb_build_object('merchant_id', v.merchant_id, 'shop_domain', v.shop_domain);
end;
$$;

-- Spec 10: true the first time a webhook id is seen.
create or replace function public.mark_webhook_seen(p_webhook_id text, p_topic text, p_shop text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.shopify_webhook_events (webhook_id, topic, shop_domain) values (p_webhook_id, p_topic, p_shop);
  return true;
exception when unique_violation then
  return false;
end;
$$;

revoke execute on function
  public.insert_sms(jsonb), public.spend_attempt(uuid), public.submit_claim(uuid, text, text),
  public.record_verified(uuid, uuid, text, uuid, text), public.record_mismatch(uuid, uuid, text),
  public.record_rejected(uuid, uuid, text), public.expire_due(timestamptz), public.hit_rate_limit(text, int, int),
  public.get_sms_results(uuid, uuid[]), public.consume_install_state(text), public.mark_webhook_seen(text, text, text)
  from public, anon, authenticated;
grant execute on function
  public.insert_sms(jsonb), public.spend_attempt(uuid), public.submit_claim(uuid, text, text),
  public.record_verified(uuid, uuid, text, uuid, text), public.record_mismatch(uuid, uuid, text),
  public.record_rejected(uuid, uuid, text), public.expire_due(timestamptz), public.hit_rate_limit(text, int, int),
  public.get_sms_results(uuid, uuid[]), public.consume_install_state(text), public.mark_webhook_seen(text, text, text)
  to service_role;

-- Objects made by later migrations start closed too.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
