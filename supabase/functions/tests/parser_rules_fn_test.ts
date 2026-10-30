import assert from "node:assert/strict";
import { FakeStore } from "../_shared/fake_store.ts";
import { handle } from "../_shared/rules.ts";
import rulesJson from "../_shared/parser_rules.json" with { type: "json" };
import { signedRequest } from "./helpers/device_signer.ts";
import { addDevice, MIN, T0, world } from "./helpers/world.ts";

const sign = (
  deviceId: string,
  key: CryptoKey,
  body = "{}",
  timestamp = T0,
  fn = "parser-rules",
) => signedRequest(fn, deviceId, key, body, { timestamp });

Deno.test("parser-rules: signed request -> 200 {ok, version, rules} from the store", async () => {
  const w = world();
  const { device, key } = await addDevice(w.store);
  const res = await handle(await sign(device.id, key.privateKey), w.deps);
  assert.equal(res.status, 200);
  const json = await res.json();
  const active = await w.store.getParserRules();
  assert.deepEqual(json, {
    ok: true,
    version: active.version,
    rules: active.rules,
  });
  assert.equal(w.logs.at(-1)?.code, "ok");
});

Deno.test("parser-rules: returns the active version (a store with version 2 rules)", async () => {
  const w = world();
  const v2 = (rulesJson as Record<string, unknown>[]).map((r) => ({
    ...r,
    version: 2,
  }));
  const store = new FakeStore(() => w.clock.now, v2);
  const { device, key } = await addDevice(store);
  const res = await handle(await sign(device.id, key.privateKey), {
    ...w.deps,
    store,
  });
  assert.equal(res.status, 200);
  const json = await res.json();
  assert.equal(json.version, 2);
  assert.deepEqual(json.rules, v2);
});

Deno.test("parser-rules: revoked device -> 403 deviceRevoked", async () => {
  const w = world();
  const { device, key } = await addDevice(w.store, "m1", "revoked");
  const res = await handle(await sign(device.id, key.privateKey), w.deps);
  assert.equal(res.status, 403);
  assert.equal((await res.json()).error, "deviceRevoked");
});

Deno.test("parser-rules: same signed check as spec 08 (unsigned, stale, wrong function, unknown device)", async () => {
  const w = world();
  const { device, key } = await addDevice(w.store);
  const code = async (req: Request) => {
    const res = await handle(req, w.deps);
    return `${res.status} ${(await res.json()).error}`;
  };
  assert.equal(
    await code(
      new Request("http://localhost/parser-rules", {
        method: "POST",
        body: "{}",
      }),
    ),
    "401 missingSignature",
  );
  assert.equal(
    await code(await sign(device.id, key.privateKey, "{}", T0 - 6 * MIN)),
    "401 staleTimestamp",
  );
  assert.equal(
    await code(
      await sign(device.id, key.privateKey, "{}", T0, "device-heartbeat"),
    ),
    "401 badSignature",
  );
  assert.equal(
    await code(await sign(crypto.randomUUID(), key.privateKey)),
    "401 unknownDevice",
  );
});

Deno.test("parser-rules: GET -> 405; a body that is not an object -> 400", async () => {
  const w = world();
  const { device, key } = await addDevice(w.store);
  const get = await handle(
    new Request("http://localhost/parser-rules", { method: "GET" }),
    w.deps,
  );
  assert.equal(get.status, 405);
  const bad = await handle(await sign(device.id, key.privateKey, "[]"), w.deps);
  assert.equal(bad.status, 400);
});
