-- Spec 12 (spec 09 records): payment sessions, claims and matches. Never deleted.

create table public.payment_sessions (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  store_id uuid not null references public.stores (id) on delete restrict,
  token_hash text not null unique,
  order_ref text not null,
  external_order_id text,
  amount_poisha bigint not null check (amount_poisha > 0),
  status text not null default 'open'
    check (status in ('open', 'pending', 'verified', 'mismatch', 'expired', 'rejected')),
  submit_deadline timestamptz not null,
  attempts_left int not null default 5 check (attempts_left between 0 and 5),
  return_url text not null,
  active_claim_id uuid,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sessions_store_order_unique unique (store_id, external_order_id)
);
create index sessions_merchant_idx on public.payment_sessions (merchant_id);
create index sessions_store_idx on public.payment_sessions (store_id);
create index sessions_open_deadline_idx on public.payment_sessions (submit_deadline) where status = 'open';

create table public.payment_claims (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  session_id uuid not null references public.payment_sessions (id) on delete restrict,
  operator text not null check (operator in ('bkash', 'nagad', 'rocket', 'upay')),
  trx_id text not null,
  status text not null default 'pending'
    check (status in ('pending', 'verified', 'mismatch', 'rejected', 'expired', 'superseded')),
  reason text,
  candidate_sms_id uuid references public.sms_messages (id) on delete restrict,
  match_deadline timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index claims_merchant_idx on public.payment_claims (merchant_id);
create index claims_session_idx on public.payment_claims (session_id);
create index claims_candidate_idx on public.payment_claims (candidate_sms_id);
-- A TrxID can be live on only one claim per merchant + operator.
create unique index claims_live_trx_unique on public.payment_claims (merchant_id, operator, trx_id)
  where status in ('pending', 'verified', 'mismatch');
create index claims_pending_deadline_idx on public.payment_claims (match_deadline) where status = 'pending';

alter table public.payment_sessions
  add constraint sessions_active_claim_fk foreign key (active_claim_id)
  references public.payment_claims (id) on delete restrict deferrable initially deferred;
create index sessions_active_claim_idx on public.payment_sessions (active_claim_id);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  claim_id uuid not null unique references public.payment_claims (id) on delete restrict,
  sms_id uuid not null unique references public.sms_messages (id) on delete restrict,
  method text not null check (method in ('auto', 'manual')),
  user_id uuid,
  note text check (char_length(note) <= 200),
  created_at timestamptz not null default now()
);
create index matches_merchant_idx on public.matches (merchant_id);

create trigger sessions_updated_at before update on public.payment_sessions
  for each row execute function public.set_updated_at();
create trigger claims_updated_at before update on public.payment_claims
  for each row execute function public.set_updated_at();
create trigger claims_trx_upper before insert or update on public.payment_claims
  for each row execute function public.normalize_trx_id();
create trigger sessions_no_delete before delete on public.payment_sessions
  for each row execute function public.block_delete();
create trigger claims_no_delete before delete on public.payment_claims
  for each row execute function public.block_delete();
create trigger matches_no_delete before delete on public.matches
  for each row execute function public.block_delete();
create trigger matches_no_update before update on public.matches
  for each row execute function public.block_update();
