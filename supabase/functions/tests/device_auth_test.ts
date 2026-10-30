import assert from "node:assert/strict";
import { utf8 } from "../_shared/crypto.ts";
import { checkDeviceRequest } from "../_shared/device_auth.ts";
import { signedRequest } from "./helpers/device_signer.ts";
import { addDevice, MIN, T0, world } from "./helpers/world.ts";

const BODY = '{"items":[]}';

async function check(req: Request, fn = "sms-ingest", now = T0) {
  const w = current!;
  const raw = new Uint8Array(await req.clone().arrayBuffer());
  return checkDeviceRequest(fn, req.headers, raw, w.store, now);
}

let current: ReturnType<typeof world> | null = null;

async function setup() {
  current = world();
  return { w: current, ...(await addDevice(current.store)) };
}

const code = (r: Awaited<ReturnType<typeof check>>) => r.ok ? "ok" : r.code;

Deno.test("valid DER signature passes and returns the device", async () => {
  const { device, key } = await setup();
  const r = await check(
    await signedRequest("sms-ingest", device.id, key.privateKey, BODY, {
      timestamp: T0,
    }),
  );
  assert.ok(r.ok);
  assert.equal(r.ok && r.device.id, device.id);
});

Deno.test("valid raw 64-byte signature passes", async () => {
  const { device, key } = await setup();
  const r = await check(
    await signedRequest("sms-ingest", device.id, key.privateKey, BODY, {
      timestamp: T0,
      format: "raw",
    }),
  );
  assert.ok(r.ok);
});

Deno.test("missingSignature (401) for each missing header", async () => {
  const { device, key } = await setup();
  for (const omit of ["X-Device-Id", "X-Timestamp", "X-Signature"] as const) {
    const r = await check(
      await signedRequest("sms-ingest", device.id, key.privateKey, BODY, {
        timestamp: T0,
        omit,
      }),
    );
    assert.deepEqual(
      r,
      { ok: false, status: 401, code: "missingSignature" },
      omit,
    );
  }
});

Deno.test("unknownDevice (401)", async () => {
  const { key } = await setup();
  const r = await check(
    await signedRequest(
      "sms-ingest",
      crypto.randomUUID(),
      key.privateKey,
      BODY,
      {
        timestamp: T0,
      },
    ),
  );
  assert.deepEqual(r, { ok: false, status: 401, code: "unknownDevice" });
});

Deno.test("deviceRevoked (403)", async () => {
  const { w, device, key } = await setup();
  await w.store.updateDevice(device.id, { status: "revoked" });
  const r = await check(
    await signedRequest("sms-ingest", device.id, key.privateKey, BODY, {
      timestamp: T0,
    }),
  );
  assert.deepEqual(r, { ok: false, status: 403, code: "deviceRevoked" });
});

Deno.test("staleTimestamp (401): 5 min 1 s old, 5 min 1 s ahead, phone 10 min fast, not a number", async () => {
  const { device, key } = await setup();
  for (const ts of [T0 - 5 * MIN - 1000, T0 + 5 * MIN + 1000, T0 + 10 * MIN]) {
    const r = await check(
      await signedRequest("sms-ingest", device.id, key.privateKey, BODY, {
        timestamp: ts,
      }),
    );
    assert.equal(code(r), "staleTimestamp", String(ts - T0));
  }
  const req = await signedRequest(
    "sms-ingest",
    device.id,
    key.privateKey,
    BODY,
  );
  req.headers.set("X-Timestamp", "soon");
  assert.equal(code(await check(req)), "staleTimestamp");
});

Deno.test("exactly 5 minutes either way is accepted", async () => {
  const { device, key } = await setup();
  for (const ts of [T0 - 5 * MIN, T0 + 5 * MIN]) {
    const r = await check(
      await signedRequest("sms-ingest", device.id, key.privateKey, BODY, {
        timestamp: ts,
      }),
    );
    assert.equal(code(r), "ok");
  }
});

Deno.test("badSignature (401): heartbeat signature replayed to sms-ingest", async () => {
  const { device, key } = await setup();
  const r = await check(
    await signedRequest("sms-ingest", device.id, key.privateKey, BODY, {
      timestamp: T0,
      signAs: "device-heartbeat",
    }),
  );
  assert.deepEqual(r, { ok: false, status: 401, code: "badSignature" });
});

Deno.test("badSignature: body changed after signing", async () => {
  const { device, key } = await setup();
  const r = await check(
    await signedRequest("sms-ingest", device.id, key.privateKey, BODY, {
      timestamp: T0,
      sendBody: '{"items":[ ]}',
    }),
  );
  assert.equal(code(r), "badSignature");
});

Deno.test("badSignature: another device's key, garbage, timestamp header changed", async () => {
  const { w, device, key } = await setup();
  const other = await addDevice(w.store);
  const r1 = await check(
    await signedRequest("sms-ingest", device.id, other.key.privateKey, BODY, {
      timestamp: T0,
    }),
  );
  assert.equal(code(r1), "badSignature");

  const r2 = await signedRequest(
    "sms-ingest",
    device.id,
    key.privateKey,
    BODY,
    {
      timestamp: T0,
    },
  );
  r2.headers.set("X-Signature", "!!!");
  assert.equal(code(await check(r2)), "badSignature");

  const r3 = await signedRequest(
    "sms-ingest",
    device.id,
    key.privateKey,
    BODY,
    {
      timestamp: T0,
    },
  );
  r3.headers.set("X-Timestamp", String(T0 + 1));
  assert.equal(code(await check(r3)), "badSignature");
});

Deno.test("check order: missing beats unknown, revoked beats stale, stale beats bad signature", async () => {
  const { w, device, key } = await setup();
  // Unknown device AND a missing signature -> missingSignature.
  const a = await signedRequest("sms-ingest", "nope", key.privateKey, BODY, {
    omit: "X-Signature",
  });
  assert.equal(code(await check(a)), "missingSignature");
  // Unknown device with a stale time and bad signature -> unknownDevice.
  const b = await signedRequest("sms-ingest", "nope", key.privateKey, BODY, {
    timestamp: T0 - 60 * MIN,
    signAs: "x",
  });
  assert.equal(code(await check(b)), "unknownDevice");
  // Stale AND bad signature -> staleTimestamp.
  const c = await signedRequest("sms-ingest", device.id, key.privateKey, BODY, {
    timestamp: T0 - 60 * MIN,
    signAs: "x",
  });
  assert.equal(code(await check(c)), "staleTimestamp");
  // Revoked AND stale AND bad signature -> deviceRevoked.
  await w.store.updateDevice(device.id, { status: "revoked" });
  assert.equal(code(await check(c)), "deviceRevoked");
});

Deno.test("the raw body bytes are what is hashed (not re-encoded JSON)", async () => {
  const { device, key } = await setup();
  const body = '{ "items" : [] }';
  const req = await signedRequest(
    "sms-ingest",
    device.id,
    key.privateKey,
    body,
    {
      timestamp: T0,
    },
  );
  const r = await checkDeviceRequest(
    "sms-ingest",
    req.headers,
    utf8(body),
    current!.store,
    T0,
  );
  assert.ok(r.ok);
});
