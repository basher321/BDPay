// Spec 15 health: 200 {ok, db, time} / 503 {ok: false, db: false}; GET only; 60 per minute per IP hash; no user data.
import assert from "node:assert/strict";
import { handle } from "../_shared/health.ts";
import type { LogEntry } from "../_shared/http.ts";
import { MemoryRateLimiter } from "../_shared/rate_limit.ts";
import { T0, world } from "./helpers/world.ts";

const get = (ip = "203.0.113.7") =>
  new Request("http://localhost/health", {
    headers: { "x-forwarded-for": `${ip}, 10.0.0.1` },
  });

function healthWorld() {
  const w = world();
  w.deps.limiter = new MemoryRateLimiter(() => w.clock.now);
  return w;
}

Deno.test("health: store read works -> 200 {ok: true, db: true, time}; no-store; nothing else in the body", async () => {
  const w = healthWorld();
  const res = await handle(get(), w.deps);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("Cache-Control"), "no-store");
  assert.deepEqual(await res.json(), {
    ok: true,
    db: true,
    time: new Date(T0).toISOString(),
  });
  assert.deepEqual(w.logs.at(-1), {
    ...w.logs.at(-1)!,
    fn: "health",
    code: "ok",
    merchantId: null,
  });
});

Deno.test("health: store read fails -> 503 {ok: false, db: false}", async () => {
  const w = healthWorld();
  w.store.getParserRules = () =>
    Promise.reject(new Error("db down with details"));
  const res = await handle(get(), w.deps);
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), { ok: false, db: false });
  assert.equal(w.logs.at(-1)?.code, "dbDown");
});

Deno.test("health: 60 per minute per IP; the 61st -> 429; another IP and the next minute are fine", async () => {
  const w = healthWorld();
  for (let i = 0; i < 60; i++) {
    assert.equal((await handle(get(), w.deps)).status, 200);
  }
  const limited = await handle(get(), w.deps);
  assert.equal(limited.status, 429);
  assert.equal((await limited.json()).error, "rateLimited");
  assert.equal((await handle(get("198.51.100.9"), w.deps)).status, 200);
  w.clock.now += 60_000;
  assert.equal((await handle(get(), w.deps)).status, 200);
});

Deno.test("health: the IP is never logged or used raw", async () => {
  const w = healthWorld();
  const keys: string[] = [];
  w.deps.limiter = { hit: (key) => (keys.push(key), Promise.resolve(true)) };
  await handle(get("203.0.113.7"), w.deps);
  assert.ok(!keys[0].includes("203.0.113.7"));
  assert.match(keys[0], /^health:[0-9a-f]{64}$/);
  assert.ok(!JSON.stringify(w.logs).includes("203.0.113"));
});

Deno.test("health: POST -> 405; no limiter configured -> 503 (plan 15 D212)", async () => {
  const w = healthWorld();
  const post = await handle(
    new Request("http://localhost/health", { method: "POST", body: "{}" }),
    w.deps,
  );
  assert.equal(post.status, 405);
  const bare = world();
  const logs: LogEntry[] = bare.logs;
  const res = await handle(get(), bare.deps);
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), { ok: false, db: false });
  assert.equal(logs.at(-1)?.code, "rateLimiterMissing");
});
