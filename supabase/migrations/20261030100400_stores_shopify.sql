-- Spec 12: connected Shopify stores, OAuth install states and seen webhooks.
-- Shopify tokens are never in a column: they live in Supabase Vault (token_secret_id points at the secret).

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  platform text not null default 'shopify' check (platform in ('shopify')),
  shop_domain text not null unique check (shop_domain ~ '^[a-z0-9][a-z0-9-]*\.myshopify\.com$'),
  status text not null default 'active' check (status in ('active', 'uninstalled')),
  last_error text,
  connected_at timestamptz not null default now(),
  token_secret_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index stores_merchant_idx on public.stores (merchant_id);
create unique index stores_one_active on public.stores (merchant_id) where status = 'active';
create trigger stores_updated_at before update on public.stores
  for each row execute function public.set_updated_at();

create table public.shopify_install_states (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants (id) on delete restrict,
  state_hash text not null unique,
  shop_domain text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index install_states_merchant_idx on public.shopify_install_states (merchant_id);

create table public.shopify_webhook_events (
  id uuid primary key default gen_random_uuid(),
  webhook_id text not null unique,
  topic text not null,
  shop_domain text not null,
  created_at timestamptz not null default now()
);
