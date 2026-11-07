-- Spec 17: the store connections migration (pgTAP; "supabase test db"). Everything is rolled back at the end.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@spec17.test'),
  ('00000000-0000-0000-0000-0000000000b1', 'b@spec17.test');
insert into public.merchants (id, owner_id, business_name) values
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a1', 'Shop A'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b1', 'Shop B');

-- An existing-style Shopify row still works.
select lives_ok(
  $$insert into public.stores (merchant_id, shop_domain)
    values ('00000000-0000-0000-0000-0000000000a2', 'spec17-a.myshopify.com')$$,
  'a Shopify row without the new columns is still valid'
);

-- An API row next to the Shopify row (one active per platform + site, not per merchant).
select lives_ok(
  $$insert into public.stores (id, merchant_id, platform, site_name, site_url, api_key_prefix, api_key_hash)
    values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a2', 'laravel',
            'Shop A site', 'https://a.example.com', 'bdp_live_abc', repeat('a', 64))$$,
  'an API connection can sit next to the Shopify store'
);

select throws_ok(
  $$insert into public.stores (merchant_id, platform, site_name, site_url, api_key_prefix, api_key_hash)
    values ('00000000-0000-0000-0000-0000000000a2', 'laravel', 'Again', 'https://a.example.com',
            'bdp_live_def', repeat('b', 64))$$,
  '23505', null, 'the same platform + site twice while active -> unique violation'
);

select lives_ok(
  $$insert into public.stores (merchant_id, platform, site_name, site_url, api_key_prefix, api_key_hash)
    values ('00000000-0000-0000-0000-0000000000a2', 'wordpress', 'Blog shop', 'https://a.example.com',
            'bdp_live_ghi', repeat('c', 64))$$,
  'the same site on another platform is allowed'
);

select throws_ok(
  $$insert into public.stores (merchant_id, platform, site_name, site_url, api_key_prefix, api_key_hash)
    values ('00000000-0000-0000-0000-0000000000a2', 'daraz', 'X shop', 'https://x.example.com',
            'bdp_live_jkl', repeat('d', 64))$$,
  '23514', null, 'an unknown platform is refused'
);

select throws_ok(
  $$insert into public.stores (merchant_id, platform, site_name, site_url)
    values ('00000000-0000-0000-0000-0000000000a2', 'django', 'No key', 'https://nokey.example.com')$$,
  '23514', null, 'an API row without a key hash is refused'
);

select throws_ok(
  $$insert into public.stores (merchant_id, platform, site_name, site_url, api_key_prefix, api_key_hash)
    values ('00000000-0000-0000-0000-0000000000a2', 'django', 'Plain http', 'http://plain.example.com',
            'bdp_live_mno', repeat('e', 64))$$,
  '23514', null, 'a non-https site URL is refused'
);

select throws_ok(
  $$insert into public.stores (merchant_id, shop_domain)
    values ('00000000-0000-0000-0000-0000000000a2', 'spec17-a2.myshopify.com')$$,
  '23505', null, 'still one active Shopify store per merchant'
);

select lives_ok(
  $$update public.stores set status = 'disabled' where id = '00000000-0000-0000-0000-0000000000c1'$$,
  'an API connection can be disabled'
);

-- Row-level security: owner B sees none of A's connections; owner A cannot read key hashes.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select is(
  (select count(*) from public.stores where merchant_id = '00000000-0000-0000-0000-0000000000a2'),
  0::bigint,
  'another merchant sees none of the connections'
);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is(
  (select count(*) from public.stores where merchant_id = '00000000-0000-0000-0000-0000000000a2'
     and site_url is not null and platform <> 'shopify'),
  2::bigint,
  'the owner sees its own API connections'
);
select throws_ok(
  $$select api_key_hash from public.stores$$,
  '42501', null, 'the key hash column is not readable by the app'
);
reset role;

select * from finish();
rollback;
