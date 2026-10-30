-- Spec 12: merchants (one per owner) and their MFS wallets.

create table public.merchants (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users (id) on delete restrict,
  business_name text not null check (char_length(btrim(business_name)) between 2 and 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger merchants_updated_at before update on public.merchants
  for each row execute function public.set_updated_at();

-- The owner check for row-level security: the merchant's owner is the signed-in user.
create or replace function public.is_owner(p_merchant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.merchants m
    where m.id = p_merchant_id and m.owner_id = (select auth.uid())
  );
$$;

create table public.wallets (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  operator text not null check (operator in ('bkash', 'nagad', 'rocket', 'upay')),
  wallet_number text not null,
  account_type text not null check (account_type in ('merchant', 'agent')),
  label text not null default '' check (char_length(label) <= 30),
  sim_slot text not null default 'unknown' check (sim_slot in ('sim1', 'sim2', 'unknown')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wallets_number_format check (
    wallet_number ~ '^01[3-9][0-9]{8}$'
    or (operator = 'rocket' and wallet_number ~ '^01[3-9][0-9]{9}$')
  ),
  constraint wallets_operator_number_unique unique (operator, wallet_number)
);
create index wallets_merchant_idx on public.wallets (merchant_id);
create unique index wallets_active_sim_unique on public.wallets (merchant_id, operator, sim_slot)
  where is_active and sim_slot <> 'unknown';
create trigger wallets_updated_at before update on public.wallets
  for each row execute function public.set_updated_at();
