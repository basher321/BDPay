-- Spec 12: SMS forwarded by merchant phones. Never deleted; the raw message fields never change.

create table public.sms_messages (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  device_id uuid not null references public.devices (id) on delete restrict,
  wallet_id uuid references public.wallets (id) on delete restrict,
  sender text not null,
  body text,
  received_at timestamptz not null,
  server_received_at timestamptz not null default now(),
  sim_slot text not null check (sim_slot in ('sim1', 'sim2', 'unknown')),
  dedupe_hash text not null,
  operator text check (operator in ('bkash', 'nagad', 'rocket', 'upay')),
  trx_id text,
  amount_poisha bigint check (amount_poisha >= 0),
  payer_number text,
  status text not null check (status in ('received', 'unmatched', 'matched', 'rejected')),
  reject_reason text check (
    reject_reason in ('senderNotTrusted', 'blocked', 'notIncoming', 'parseFailed', 'hashMismatch', 'tooOld')
  ),
  parser_version int not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sms_merchant_dedupe_unique unique (merchant_id, dedupe_hash),
  constraint sms_rejected_reason check ((status = 'rejected') = (reject_reason is not null))
);
create index sms_merchant_idx on public.sms_messages (merchant_id);
create index sms_device_idx on public.sms_messages (device_id);
create index sms_wallet_idx on public.sms_messages (wallet_id);
create index sms_unmatched_trx_idx on public.sms_messages (merchant_id, operator, trx_id)
  where status = 'unmatched';

create trigger sms_updated_at before update on public.sms_messages
  for each row execute function public.set_updated_at();
create trigger sms_trx_upper before insert or update on public.sms_messages
  for each row execute function public.normalize_trx_id();
create trigger sms_no_delete before delete on public.sms_messages
  for each row execute function public.block_delete();

create or replace function public.sms_immutable_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.sender is distinct from old.sender or new.body is distinct from old.body
     or new.received_at is distinct from old.received_at or new.dedupe_hash is distinct from old.dedupe_hash then
    raise exception 'the raw SMS fields never change';
  end if;
  return new;
end;
$$;
create trigger sms_immutable before update on public.sms_messages
  for each row execute function public.sms_immutable_fields();
