-- Spec 14: the three timed jobs, every 5 minutes, with pg_cron + pg_net.
-- No URL or secret is written here: the job reads functions_url and cron_secret from Supabase Vault at run time.
-- Without those Vault secrets (local development) the job does nothing and does not fail.
-- (Spec 12 had planned schedules for spec 15; spec 14 brings them forward - plan 14 D182.)

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- Not exposed through the API (only the schemas listed in the API settings are).
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Calls one BDPay cron Edge Function with the X-Cron-Secret header. Returns true when a request was queued,
-- false when the name is not one of the three or the Vault secrets are missing. Never raises for those cases.
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
  -- Only these three: the secret can never be sent to any other function or address.
  if p_fn is null or p_fn not in ('claims-expire', 'shopify-sync', 'alerts-check') then
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

-- cron.schedule with an existing job name replaces that job, so applying this again is safe.
-- The stored command holds only the function name (no URL, no secret).
select cron.schedule('bdpay-claims-expire', '*/5 * * * *', $cron$select private.call_cron_function('claims-expire')$cron$);
select cron.schedule('bdpay-shopify-sync', '*/5 * * * *', $cron$select private.call_cron_function('shopify-sync')$cron$);
select cron.schedule('bdpay-alerts-check', '*/5 * * * *', $cron$select private.call_cron_function('alerts-check')$cron$);
