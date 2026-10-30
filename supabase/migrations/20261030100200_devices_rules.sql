-- Spec 12: merchant phones (public keys only) and the global SMS parser rules.

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  name text not null check (char_length(name) between 1 and 30),
  install_id uuid not null,
  public_key_spki text not null,
  status text not null default 'active' check (status in ('active', 'revoked')),
  app_version text not null default '',
  android_version text not null default '',
  last_seen_at timestamptz not null default now(),
  last_sms_permission boolean,
  last_monitoring boolean,
  last_battery_ok boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint devices_merchant_install_unique unique (merchant_id, install_id)
);
create index devices_merchant_idx on public.devices (merchant_id);
create trigger devices_updated_at before update on public.devices
  for each row execute function public.set_updated_at();

create table public.parser_rules (
  id uuid primary key default gen_random_uuid(),
  version int not null unique check (version >= 1),
  rules jsonb not null,
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index parser_rules_one_active on public.parser_rules (is_active) where is_active;
