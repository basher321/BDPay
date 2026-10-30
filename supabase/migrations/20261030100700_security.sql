-- Spec 12 security: row-level security on every table, owner-only access for the app, nothing for anon.
-- The Edge Functions use the service role (bypasses RLS) and only through the Store / the functions below.

-- RLS on (and forced) everywhere.
alter table public.merchants enable row level security;
alter table public.wallets enable row level security;
alter table public.devices enable row level security;
alter table public.parser_rules enable row level security;
alter table public.sms_messages enable row level security;
alter table public.stores enable row level security;
alter table public.shopify_install_states enable row level security;
alter table public.shopify_webhook_events enable row level security;
alter table public.payment_sessions enable row level security;
alter table public.payment_claims enable row level security;
alter table public.matches enable row level security;
alter table public.order_syncs enable row level security;
alter table public.alerts enable row level security;
alter table public.audit_log enable row level security;
alter table public.rate_limits enable row level security;

alter table public.merchants force row level security;
alter table public.wallets force row level security;
alter table public.devices force row level security;
alter table public.sms_messages force row level security;
alter table public.stores force row level security;
alter table public.shopify_install_states force row level security;
alter table public.payment_sessions force row level security;
alter table public.payment_claims force row level security;
alter table public.matches force row level security;
alter table public.order_syncs force row level security;
alter table public.alerts force row level security;
alter table public.audit_log force row level security;

-- anon: nothing at all.
revoke all on all tables in schema public from anon;

-- authenticated: start from nothing, then grant exactly what the app needs.
revoke all on all tables in schema public from authenticated;

grant select, insert on public.merchants to authenticated;
grant update (business_name) on public.merchants to authenticated;
create policy merchants_select_own on public.merchants
  for select to authenticated using (owner_id = (select auth.uid()));
create policy merchants_insert_self on public.merchants
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy merchants_update_own on public.merchants
  for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

grant select, insert, update on public.wallets to authenticated;
create policy wallets_select_own on public.wallets
  for select to authenticated using (public.is_owner(merchant_id));
create policy wallets_insert_own on public.wallets
  for insert to authenticated with check (public.is_owner(merchant_id));
create policy wallets_update_own on public.wallets
  for update to authenticated using (public.is_owner(merchant_id)) with check (public.is_owner(merchant_id));

-- Read-only for the owner (the app never writes these; the Edge Functions do).
grant select on public.devices, public.sms_messages, public.payment_sessions, public.payment_claims,
  public.matches, public.order_syncs, public.alerts, public.audit_log to authenticated;
create policy devices_select_own on public.devices for select to authenticated using (public.is_owner(merchant_id));
create policy sms_select_own on public.sms_messages for select to authenticated using (public.is_owner(merchant_id));
create policy sessions_select_own on public.payment_sessions
  for select to authenticated using (public.is_owner(merchant_id));
create policy claims_select_own on public.payment_claims
  for select to authenticated using (public.is_owner(merchant_id));
create policy matches_select_own on public.matches for select to authenticated using (public.is_owner(merchant_id));
create policy order_syncs_select_own on public.order_syncs
  for select to authenticated using (public.is_owner(merchant_id));
create policy alerts_select_own on public.alerts for select to authenticated using (public.is_owner(merchant_id));
create policy audit_select_own on public.audit_log for select to authenticated using (public.is_owner(merchant_id));

-- stores: readable by the owner except token_secret_id (column privileges).
grant select (id, merchant_id, platform, shop_domain, status, last_error, connected_at, created_at, updated_at)
  on public.stores to authenticated;
create policy stores_select_own on public.stores for select to authenticated using (public.is_owner(merchant_id));

-- parser_rules: any signed-in user can read the active rules.
grant select on public.parser_rules to authenticated;
create policy parser_rules_select_active on public.parser_rules
  for select to authenticated using (is_active);

-- shopify_install_states, shopify_webhook_events, rate_limits: no client access (no grants, no policies).

-- Functions: nothing callable by the public roles unless granted below.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.is_owner(uuid) to authenticated;
