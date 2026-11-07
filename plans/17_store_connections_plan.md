# Plan 17 Store connections (all platforms)

Decisions
- D300 Reuse public.stores for every connection, so payment_sessions.store_id and order_syncs work unchanged.
  platform CHECK extended; shop_domain only for Shopify; stores_kind_fields keeps the two row kinds apart.
- D301 No Vault for API connections: the API key is stored as SHA-256 only; the webhook secret and the pay
  token of an API order are HMACs of PAY_TOKEN_SECRET, so nothing secret is stored and links can be rebuilt.
- D302 Webhook retries reuse order_syncs and the spec 10 waits; a new cron function store-webhooks-sync runs
  them (the cron helper's allow-list grows by one). Shopify syncs are skipped there (spec 10b).
- D303 The Shopify section and its tests stay as they are; the new section sits above it and the picker's
  Shopify entry points to it with a toast.
- D304 The app talks to store-connections only (no table reads); the new columns are granted for reading,
  api_key_hash never.

Steps
1. Server: types, Store additions (FakeStore, PgStore, contract suite), connections.ts, store_connections.ts,
   merchant_api.ts, webhook_notifier.ts, store_webhooks_sync.ts, three index.ts, config.toml, store factory.
2. Tests: store_connections_test.ts (handlers, webhook, sync), contract tests, runbook lists.
3. Migration 20261107100000_store_connections.sql + supabase/tests/store_connections_test.sql + schedules test.
4. App: StorePlatform / StoreConnection, ConnectionsRepository (mock + Supabase), providers, ARB strings,
   ConnectionsSection, add sheet (picker, form, keys once), detail sheet (webhook, new key, disable), guide.
5. Tests: validators, widgets, repository mapping. flutter analyze, flutter test, deno check/lint/fmt/test.
6. CI db-tests on push (migration + pgTAP + PgStore contract), then db push and function deploy.

Deploy (owner terminal or Claude Code once the CLI is logged in)
    supabase db push
    supabase functions deploy merchant-api --no-verify-jwt
    supabase functions deploy store-webhooks-sync --no-verify-jwt
    supabase functions deploy store-connections
    (PAY_TOKEN_SECRET and PAY_PAGE_URL must be set; see production runbook step 4.)
