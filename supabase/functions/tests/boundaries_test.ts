// CLAUDE.md Backend rules: Edge Function logic talks only to the Store interface; no SQL or Supabase calls in
// handlers. Reads the source files (needs --allow-read, plan D77).
import assert from "node:assert/strict";

const root = new URL("../", import.meta.url);
const CORE = [
  "register",
  "ingest",
  "heartbeat",
  "deactivate",
  "rules",
  "health",
  "rate_limit",
  "pay_session",
  "claim_review",
  "sms_status",
  "claims_expire",
  "session_view",
  "token",
  "cors",
  "trx_format",
  "notifier",
  "match_rules",
  "matcher",
  "device_auth",
  "parser",
  "wallet_resolve",
  "crypto",
  "http",
]
  .map((f) => `_shared/${f}.ts`);
const INDEX = [
  "device-register",
  "sms-ingest",
  "device-heartbeat",
  "device-deactivate",
  "parser-rules",
  "health",
  "pay-session",
  "claim-review",
  "sms-status",
  "claims-expire",
].map((f) => `${f}/index.ts`);

const read = (path: string) => Deno.readTextFile(new URL(path, root));

/** Source without comments, so a comment mentioning SQL does not count. */
const code = (src: string) =>
  src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");

Deno.test("core files and index.ts: no SQL, no Supabase client, no fetch, no remote imports", async () => {
  for (const path of [...CORE, ...INDEX]) {
    const src = code(await read(path));
    assert.ok(
      !/\b(SELECT|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM)\b/.test(src),
      `${path}: SQL`,
    );
    assert.ok(
      !/supabase-js|@supabase\/|createClient|postgres|npm:|jsr:|https?:\/\/[^"'\s]*\.(ts|js)/
        .test(src),
      `${path}: client/remote import`,
    );
    assert.ok(!/\bfetch\(/.test(src), `${path}: fetch`);
  }
});

Deno.test("core files do not read the environment; index.ts reads only BDPAY_FAKE_STORE via depsFromEnv", async () => {
  for (const path of CORE) {
    assert.ok(!/Deno\.env/.test(code(await read(path))), path);
  }
  for (const path of INDEX) {
    const src = code(await read(path));
    assert.ok(
      /serveFunction\(FN, handle, \(\) => depsFromEnv\(\(k\) => Deno\.env\.get\(k\)\)\)/
        .test(src),
      path,
    );
  }
});

Deno.test("only fake_store.ts (and tests) import parser_rules.json; handlers get rules through the Store", async () => {
  for (
    const path of [
      ...CORE,
      ...INDEX,
      "_shared/store.ts",
      "_shared/matcher.ts",
      "_shared/user_auth.ts",
      "_shared/types.ts",
    ]
  ) {
    assert.ok(!code(await read(path)).includes("parser_rules.json"), path);
  }
  assert.ok(
    (await read("_shared/fake_store.ts")).includes("parser_rules.json"),
  );
});

Deno.test("no console output except the logger in http.ts", async () => {
  for (
    const path of [
      ...CORE,
      ...INDEX,
      "_shared/fake_store.ts",
      "_shared/store.ts",
      "_shared/matcher.ts",
      "_shared/user_auth.ts",
    ]
  ) {
    const src = code(await read(path));
    const count = (src.match(/console\./g) ?? []).length;
    assert.equal(count, path === "_shared/http.ts" ? 1 : 0, path);
  }
});
