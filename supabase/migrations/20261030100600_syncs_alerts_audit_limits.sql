-- Spec 12: Shopify order syncs, alerts, the audit log and rate-limit counters.

create table public.order_syncs (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  session_id uuid not null unique references public.payment_sessions (id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'done', 'failed')),
  attempts int not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index order_syncs_merchant_idx on public.order_syncs (merchant_id);
create index order_syncs_due_idx on public.order_syncs (next_attempt_at) where status = 'pending';
create trigger order_syncs_updated_at before update on public.order_syncs
  for each row execute function public.set_updated_at();

create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  kind text not null
    check (kind in ('phoneSilent', 'monitoringOff', 'noActiveDevice', 'shopifyReconnect', 'reviewWaiting', 'syncFailed')),
  status text not null default 'open' check (status in ('open', 'resolved')),
  opened_at timestamptz not null default now(),
  last_sent_at timestamptz,
  send_count int not null default 0,
  resolved_at timestamptz,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index alerts_merchant_idx on public.alerts (merchant_id);
create unique index alerts_one_open_condition on public.alerts (merchant_id, kind)
  where status = 'open' and kind <> 'syncFailed';
create unique index alerts_one_sync_failed on public.alerts (merchant_id, (details ->> 'syncId'))
  where kind = 'syncFailed';
create trigger alerts_updated_at before update on public.alerts
  for each row execute function public.set_updated_at();

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid references public.merchants (id) on delete restrict,
  actor_type text not null check (actor_type in ('user', 'device', 'system')),
  actor_id text,
  action text not null,
  entity text not null,
  entity_id text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_merchant_idx on public.audit_log (merchant_id, created_at);
create index audit_action_idx on public.audit_log (action, created_at);
create trigger audit_no_delete before delete on public.audit_log
  for each row execute function public.block_delete();
create trigger audit_no_update before update on public.audit_log
  for each row execute function public.block_update();

-- Every payment session status change leaves one audit row.
create or replace function public.audit_session_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status then
    insert into public.audit_log (merchant_id, actor_type, actor_id, action, entity, entity_id, data)
    values (new.merchant_id, 'system', null, 'session.status', 'payment_session', new.id::text,
            jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  return new;
end;
$$;
create trigger sessions_status_audit after update on public.payment_sessions
  for each row execute function public.audit_session_status();

create table public.rate_limits (
  key text not null,
  window_start timestamptz not null,
  count int not null default 0,
  primary key (key, window_start)
);
