-- Spec 17: store connections for every website platform. Shopify rows (spec 10) keep working unchanged.
-- Approved by the owner on 2026-11-07: CHECK constraints and one partial unique index on stores are replaced.
-- No table, column or row is removed. API keys are stored only as SHA-256 (api_key_hash); webhook secrets are
-- derived from PAY_TOKEN_SECRET in the functions and never stored.

alter table public.stores
  add column site_name text check (site_name is null or char_length(site_name) between 2 and 60),
  add column site_url text check (site_url is null or (site_url ~ '^https:/{2}' and char_length(site_url) <= 300)),
  add column webhook_url text check (webhook_url is null or (webhook_url ~ '^https:/{2}' and char_length(webhook_url) <= 300)),
  add column api_key_prefix text check (api_key_prefix is null or char_length(api_key_prefix) = 12),
  add column api_key_hash text unique check (api_key_hash is null or api_key_hash ~ '^[0-9a-f]{64}$'),
  add column secret_version int not null default 1 check (secret_version >= 1);

-- The platform list (spec 17; same values as the Dart enum and the TypeScript PLATFORMS list).
alter table public.stores drop constraint stores_platform_check;
alter table public.stores add constraint stores_platform_check check (platform in (
  'shopify', 'wordpress', 'webflow', 'framer', 'wix', 'squarespace', 'bubble', 'drupal', 'joomla',
  'hubspot', 'duda', 'react', 'nextjs', 'vue', 'laravel', 'nodejs', 'django', 'ghost', 'magento',
  'prestashop', 'webstudio', 'astro', 'sveltekit', 'nuxt', 'other'));

-- shop_domain is only for Shopify rows now.
alter table public.stores alter column shop_domain drop not null;
alter table public.stores drop constraint stores_shop_domain_check;
alter table public.stores add constraint stores_shop_domain_check
  check (shop_domain is null or shop_domain ~ '^[a-z0-9][a-z0-9-]*\.myshopify\.com$');

-- A Shopify row has a shop domain and no API key; an API row has a site and a key and no shop domain.
alter table public.stores add constraint stores_kind_fields check (
  (platform = 'shopify' and shop_domain is not null and api_key_hash is null)
  or (platform <> 'shopify' and shop_domain is null and site_name is not null and site_url is not null
      and api_key_hash is not null and api_key_prefix is not null));

-- 'disabled': the merchant turned an API connection off (new checkouts refused, old records kept).
alter table public.stores drop constraint stores_status_check;
alter table public.stores add constraint stores_status_check
  check (status in ('active', 'uninstalled', 'disabled'));

-- One active Shopify store per merchant (as before); API connections: one active per platform + site.
drop index public.stores_one_active;
create unique index stores_one_active_shopify on public.stores (merchant_id)
  where status = 'active' and platform = 'shopify';
create unique index stores_one_active_site on public.stores (merchant_id, platform, site_url)
  where status = 'active' and platform <> 'shopify';

-- The app reads connections only through the store-connections function. The owner may still read the
-- public columns; api_key_hash is never granted.
grant select (site_name, site_url, webhook_url, api_key_prefix) on public.stores to authenticated;

-- store-webhooks-sync joins the timed jobs (the list in private.call_cron_function grows by one).
create or replace function private.call_cron_function(p_fn text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  -- Only these four: the secret can never be sent to any other function or address.
  if p_fn is null or p_fn not in ('claims-expire', 'shopify-sync', 'alerts-check', 'store-webhooks-sync') then
    return false;
  end if;

  select ds.decrypted_secret into v_url
  from vault.decrypted_secrets ds
  where ds.name = 'functions_url';

  select ds.decrypted_secret into v_secret
  from vault.decrypted_secrets ds
  where ds.name = 'cron_secret';

  if v_url is null or btrim(v_url) = '' or v_secret is null or v_secret = '' then
    return false; -- not set up (local): nothing to do, nothing logged
  end if;

  perform net.http_post(
    url := rtrim(btrim(v_url), '/') || '/' || p_fn,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-Cron-Secret', v_secret),
    timeout_milliseconds := 10000
  );
  return true;
end;
$$;

revoke execute on function private.call_cron_function(text) from public, anon, authenticated;

select cron.schedule('bdpay-store-webhooks-sync', '*/5 * * * *',
  $cron$select private.call_cron_function('store-webhooks-sync')$cron$);
