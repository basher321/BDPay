-- Spec 14: the schedules migration (pgTAP; run with "supabase test db --local"). Everything happens inside this
-- transaction and is rolled back: the Vault secrets created below never exist outside it, and pg_net only sends
-- committed requests, so nothing is ever called.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

select has_extension('pg_cron', 'pg_cron is installed');
select has_extension('pg_net', 'pg_net is installed');

select results_eq(
  $$select jobname::text, schedule::text from cron.job where jobname like 'bdpay-%' order by jobname$$,
  $$values ('bdpay-alerts-check', '*/5 * * * *'), ('bdpay-claims-expire', '*/5 * * * *'),
           ('bdpay-shopify-sync', '*/5 * * * *')$$,
  'three jobs, every 5 minutes'
);

select is(
  (select count(*) from cron.job
   where jobname like 'bdpay-%'
     and (command ilike '%http%' or command ilike '%secret%' or command ilike '%supabase.co%')),
  0::bigint,
  'no URL or secret in the stored job commands'
);

-- Local: no Vault secrets -> nothing happens.
select is(
  (select count(*) from vault.secrets where name in ('functions_url', 'cron_secret')),
  0::bigint,
  'precondition: the local database has no schedule secrets'
);

create temp table queue_before as select count(*) as n from net.http_request_queue;

select is(private.call_cron_function('claims-expire'), false, 'missing Vault secrets -> false, no error');
select is(
  (select count(*) from net.http_request_queue),
  (select n from queue_before),
  'missing Vault secrets -> no request queued'
);
select is(private.call_cron_function('somewhere-else'), false, 'an unknown function name is refused');

-- With both secrets (inside this transaction only): one request to the right URL, with the header.
select vault.create_secret('http://127.0.0.1:9/functions/v1/', 'functions_url');
select vault.create_secret('test-cron-secret', 'cron_secret');

select is(private.call_cron_function('alerts-check'), true, 'with Vault secrets -> a request is queued');
select is(
  (select count(*) from net.http_request_queue where url = 'http://127.0.0.1:9/functions/v1/alerts-check'
     and headers ->> 'X-Cron-Secret' = 'test-cron-secret'),
  1::bigint,
  'the request goes to functions_url/<name> with X-Cron-Secret'
);

select ok(
  not has_function_privilege('anon', 'private.call_cron_function(text)', 'execute'),
  'anon cannot execute the cron call function'
);
select ok(
  not has_function_privilege('authenticated', 'private.call_cron_function(text)', 'execute'),
  'authenticated cannot execute the cron call function'
);
select ok(not has_schema_privilege('anon', 'private', 'usage'), 'anon has no access to schema private');
select ok(not has_schema_privilege('authenticated', 'private', 'usage'), 'authenticated has no access to schema private');

select * from finish();
rollback;
