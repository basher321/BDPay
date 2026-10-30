// Spec 12a: picks the Store for every index.ts.
//   BDPAY_FAKE_STORE=1                          -> FakeStore (tests, local demos)
//   SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY    -> PgStore (the real database; Supabase sets both for functions)
//   otherwise                                   -> null (index.ts answers 503 storeNotReady)
// Env values are read only here; nothing about them is logged.

import { depsFromEnv as fakeDeps } from "./fake_store.ts";
import { releaseFromEnv } from "./heartbeat.ts";
import { consoleLogger, type Deps } from "./http.ts";
import { StoreMatcher } from "./matcher.ts";
import { NoopNotifier } from "./notifier.ts";
import { PgStore } from "./pg_store.ts";
import { storeLimiter } from "./rate_limit.ts";
import { SupabaseUserVerifier } from "./supabase_user_verifier.ts";

let real: Deps | null = null;

export function depsFromEnv(
  get: (name: string) => string | undefined,
): Deps | null {
  if (get("BDPAY_FAKE_STORE") === "1") return fakeDeps(get);
  const url = get("SUPABASE_URL");
  const key = get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;
  if (real === null) {
    const store = PgStore.fromEnv(url, key);
    const notifier = new NoopNotifier();
    real = {
      store,
      users: new SupabaseUserVerifier(url, key),
      matcher: new StoreMatcher(store, notifier, consoleLogger),
      now: Date.now,
      log: consoleLogger,
      limiter: storeLimiter(store),
      notifier,
      release: releaseFromEnv(get),
      config: {
        payPageOrigin: get("PAY_PAGE_ORIGIN"),
        cronSecret: get("CRON_SECRET"),
        rateLimitPepper: get("RATE_LIMIT_PEPPER"),
      },
    };
  }
  return real;
}
