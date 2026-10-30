// Spec 08: never log SMS body, sender, TrxID, payer number, keys or tokens. Log only fn, requestId, code and
// merchantId. Every handler runs its success and error paths with a recording logger; the logs and every error
// response are searched for the secret fixture strings.
import assert from "node:assert/strict";
import { handle as deactivate } from "../_shared/deactivate.ts";
import { handle as heartbeat } from "../_shared/heartbeat.ts";
import { type LogEntry, serveFunction } from "../_shared/http.ts";
import { handle as ingest } from "../_shared/ingest.ts";
import { dedupeHash } from "../_shared/parser.ts";
import { handle as health } from "../_shared/health.ts";
import { MemoryRateLimiter } from "../_shared/rate_limit.ts";
import { handle as register } from "../_shared/register.ts";
import { handle as parserRules } from "../_shared/rules.ts";
import { newDeviceKey, signedRequest } from "./helpers/device_signer.ts";
import { T0, USER_TOKEN, world } from "./helpers/world.ts";

const SENDER = "bKash";
const BODY = "You have received Tk 7,777.00 from 01798765432. TrxID ZQ55SECRET";
const SECRETS = [
  "ZQ55SECRET",
  "01798765432",
  "7,777",
  "You have received",
  USER_TOKEN,
];

function assertClean(
  label: string,
  logs: LogEntry[],
  texts: string[],
  extra: string[] = [],
) {
  for (const entry of logs) {
    assert.deepEqual(Object.keys(entry).sort(), [
      "code",
      "fn",
      "merchantId",
      "requestId",
    ], label);
  }
  const all = JSON.stringify(logs) + texts.join("\n");
  for (const s of [...SECRETS, ...extra]) {
    assert.ok(!all.includes(s), `${label}: leaked ${s.slice(0, 12)}`);
  }
}

Deno.test("no secret in any log line or error body, on every path", async () => {
  const w = world();
  const texts: string[] = [];
  const run = async (p: Promise<Response>) => {
    const res = await p;
    if (res.status !== 200) texts.push(await res.text());
    return res;
  };

  // register: ok, bad token, bad key, not JSON with SMS text in it.
  const key = await newDeviceKey();
  const regBody = {
    installId: crypto.randomUUID(),
    deviceName: "Phone",
    publicKeySpki: key.publicKeySpki,
    appVersion: "1.0.0",
    androidVersion: "14",
  };
  const regReq = (token: string, body: string) =>
    new Request("http://localhost/device-register", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      body,
    });
  const ok = await (await run(
    register(regReq(USER_TOKEN, JSON.stringify(regBody)), w.deps),
  )).json();
  await run(
    register(regReq("wrong-token-SECRET", JSON.stringify(regBody)), w.deps),
  );
  await run(
    register(
      regReq(USER_TOKEN, JSON.stringify({ ...regBody, publicKeySpki: "AAAA" })),
      w.deps,
    ),
  );
  await run(register(regReq(USER_TOKEN, `{"x": "${BODY}"`), w.deps));

  // ingest: ok, duplicate, bad JSON containing SMS text, bad shape, bad signature.
  const items = [{
    localId: "l1",
    sender: SENDER,
    body: BODY,
    receivedAt: new Date(T0).toISOString(),
    simSlot: "sim1",
    dedupeHash: await dedupeHash(SENDER, BODY),
  }];
  const sign = (fn: string, body: string, signAs?: string) =>
    signedRequest(fn, ok.deviceId, key.privateKey, body, {
      timestamp: T0,
      signAs,
    });
  await run(
    ingest(await sign("sms-ingest", JSON.stringify({ items })), w.deps),
  );
  await run(
    ingest(await sign("sms-ingest", JSON.stringify({ items })), w.deps),
  );
  await run(ingest(await sign("sms-ingest", `{"items": [${BODY}]}`), w.deps));
  await run(
    ingest(
      await sign(
        "sms-ingest",
        JSON.stringify({ items: [{ ...items[0], simSlot: BODY }] }),
      ),
      w.deps,
    ),
  );
  await run(
    ingest(
      await sign("sms-ingest", JSON.stringify({ items }), "device-heartbeat"),
      w.deps,
    ),
  );

  // heartbeat and deactivate.
  const hb = JSON.stringify({
    appVersion: "1.0.0",
    smsPermission: true,
    batteryOptimizationOff: true,
    monitoring: true,
    queueCount: 0,
  });
  await run(heartbeat(await sign("device-heartbeat", hb), w.deps));
  await run(
    heartbeat(
      await sign("device-heartbeat", `{"appVersion": "${BODY}"}`),
      w.deps,
    ),
  );
  // parser-rules (spec 13a): ok, a body with SMS text in it, a signature for another function.
  await run(parserRules(await sign("parser-rules", "{}"), w.deps));
  await run(parserRules(await sign("parser-rules", `["${BODY}"]`), w.deps));
  await run(
    parserRules(await sign("parser-rules", "{}", "device-heartbeat"), w.deps),
  );
  // health (spec 15): ok and 405; the caller's IP must not reach a log.
  w.deps.limiter = new MemoryRateLimiter(() => T0);
  await run(
    health(
      new Request("http://localhost/health", {
        headers: { "x-forwarded-for": "203.0.113.77" },
      }),
      w.deps,
    ),
  );
  await run(
    health(
      new Request("http://localhost/health", { method: "POST", body: BODY }),
      w.deps,
    ),
  );
  assert.ok(!JSON.stringify(w.logs).includes("203.0.113.77"));
  await run(deactivate(await sign("device-deactivate", "{}"), w.deps));

  assert.ok(w.logs.length >= 12);
  assert.ok(w.logs.every((l) => typeof l.code === "string"));
  assertClean("handlers", w.logs, texts, [
    key.publicKeySpki,
    "wrong-token-SECRET",
  ]);
  // The audit log holds no key, token or SMS fields either.
  assertClean("audit", [], [JSON.stringify(w.store.audit)], [
    key.publicKeySpki,
  ]);
});

Deno.test("a store that throws mid-ingest -> 500; nothing secret logged", async () => {
  const w = world();
  const logs: LogEntry[] = [];
  const key = await newDeviceKey();
  const device = await w.store.createDevice({
    merchantId: "m1",
    name: "p",
    installId: crypto.randomUUID(),
    publicKeySpki: key.publicKeySpki,
    status: "active",
    appVersion: "1",
    androidVersion: "14",
    lastSeenAt: new Date(T0).toISOString(),
  });
  w.store.insertSms = () =>
    Promise.reject(new Error(`insert failed for ${BODY}`));
  const serve = serveFunction(
    "sms-ingest",
    ingest,
    () => w.deps,
    (e) => logs.push(e),
  );
  const items = [{
    localId: "l1",
    sender: SENDER,
    body: BODY,
    receivedAt: new Date(T0).toISOString(),
    simSlot: "sim1",
    dedupeHash: await dedupeHash(SENDER, BODY),
  }];
  const res = await serve(
    await signedRequest(
      "sms-ingest",
      device.id,
      key.privateKey,
      JSON.stringify({ items }),
      {
        timestamp: T0,
      },
    ),
  );
  assert.equal(res.status, 500);
  assertClean("throwing store", logs, [await res.text()]);
});
