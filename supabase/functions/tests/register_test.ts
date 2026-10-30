import assert from "node:assert/strict";
import { handle as deactivate } from "../_shared/deactivate.ts";
import { handle as heartbeat } from "../_shared/heartbeat.ts";
import { handle } from "../_shared/register.ts";
import {
  bytesToBase64,
  newDeviceKey,
  signedRequest,
} from "./helpers/device_signer.ts";
import { NO_MERCHANT_TOKEN, T0, USER_TOKEN, world } from "./helpers/world.ts";

function registerReq(token: string | null, body: unknown): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (token !== null) headers.set("Authorization", `Bearer ${token}`);
  return new Request("http://localhost/device-register", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

async function body(installId = crypto.randomUUID(), name = "দোকানের ফোন") {
  const key = await newDeviceKey();
  return {
    key,
    body: {
      installId,
      deviceName: name,
      publicKeySpki: key.publicKeySpki,
      appVersion: "1.0.0",
      androidVersion: "14",
    },
  };
}

const HB = JSON.stringify({
  appVersion: "1.0.0",
  smsPermission: true,
  batteryOptimizationOff: true,
  monitoring: true,
  queueCount: 0,
});

Deno.test("badUserToken (401): no token, unknown token, not Bearer", async () => {
  const w = world();
  const { body: b } = await body();
  for (const req of [registerReq(null, b), registerReq("nope", b)]) {
    const res = await handle(req, w.deps);
    assert.equal(res.status, 401);
    assert.equal((await res.json()).error, "badUserToken");
  }
  const basic = registerReq(null, b);
  basic.headers.set("Authorization", `Basic ${USER_TOKEN}`);
  assert.equal((await handle(basic, w.deps)).status, 401);
});

Deno.test("noMerchant (403)", async () => {
  const w = world();
  const res = await handle(
    registerReq(NO_MERCHANT_TOKEN, (await body()).body),
    w.deps,
  );
  assert.equal(res.status, 403);
  assert.deepEqual(await res.json(), {
    ok: false,
    error: "noMerchant",
    message: "This user does not own a merchant.",
  });
});

Deno.test("new device: 200 with deviceId, merchantId, serverTime, rulesVersion; audited", async () => {
  const w = world();
  const { body: b } = await body();
  const res = await handle(registerReq(USER_TOKEN, b), w.deps);
  assert.equal(res.status, 200);
  const out = await res.json();
  assert.equal(out.ok, true);
  assert.equal(out.merchantId, "m1");
  assert.equal(out.serverTime, new Date(T0).toISOString());
  assert.equal(out.rulesVersion, 1);
  const d = w.store.devices.get(out.deviceId)!;
  assert.equal(d.status, "active");
  assert.equal(d.name, "দোকানের ফোন");
  assert.equal(d.publicKeySpki, b.publicKeySpki);
  assert.equal(w.store.audit.length, 1);
  assert.equal(w.store.audit[0].action, "device.register");
  assert.equal(w.store.audit[0].actorType, "user");
  assert.ok(!JSON.stringify(w.store.audit).includes(b.publicKeySpki));
});

Deno.test("same installId rotates the key and keeps the deviceId", async () => {
  const w = world();
  const installId = crypto.randomUUID();
  const first = await body(installId);
  const a = await (await handle(registerReq(USER_TOKEN, first.body), w.deps))
    .json();
  const second = await body(installId, "নতুন নাম");
  const b = await (await handle(registerReq(USER_TOKEN, second.body), w.deps))
    .json();
  assert.equal(b.deviceId, a.deviceId);
  assert.equal(w.store.devices.size, 1);
  assert.equal(w.store.devices.get(a.deviceId)!.name, "নতুন নাম");
  // The new key signs; the old key no longer does.
  const ok = await heartbeat(
    await signedRequest(
      "device-heartbeat",
      a.deviceId,
      second.key.privateKey,
      HB,
      {
        timestamp: T0,
      },
    ),
    w.deps,
  );
  assert.equal(ok.status, 200);
  const old = await heartbeat(
    await signedRequest(
      "device-heartbeat",
      a.deviceId,
      first.key.privateKey,
      HB,
      {
        timestamp: T0,
      },
    ),
    w.deps,
  );
  assert.equal((await old.json()).error, "badSignature");
});

Deno.test("4th device -> deviceLimit (409); a revoked device does not count", async () => {
  const w = world();
  const ids: string[] = [];
  for (let i = 0; i < 3; i++) {
    const res = await handle(
      registerReq(USER_TOKEN, (await body()).body),
      w.deps,
    );
    ids.push((await res.json()).deviceId);
  }
  const fourth = await handle(
    registerReq(USER_TOKEN, (await body()).body),
    w.deps,
  );
  assert.equal(fourth.status, 409);
  assert.equal((await fourth.json()).error, "deviceLimit");
  await w.store.updateDevice(ids[0], { status: "revoked" });
  const again = await handle(
    registerReq(USER_TOKEN, (await body()).body),
    w.deps,
  );
  assert.equal(again.status, 200);
  // Another merchant's devices don't count.
  const m2 = await handle(
    registerReq("token-owner-m2", (await body()).body),
    w.deps,
  );
  assert.equal(m2.status, 200);
});

Deno.test("bad key -> badPublicKey (400): garbage, P-384, RSA", async () => {
  const w = world();
  const p384 = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-384" },
    true,
    ["sign"],
  );
  const p384Spki = bytesToBase64(
    new Uint8Array(await crypto.subtle.exportKey("spki", p384.publicKey)),
  );
  const rsa = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign"],
  );
  const rsaSpki = bytesToBase64(
    new Uint8Array(await crypto.subtle.exportKey("spki", rsa.publicKey)),
  );
  for (const k of ["bm90IGEga2V5", p384Spki, rsaSpki]) {
    const b = (await body()).body;
    const res = await handle(
      registerReq(USER_TOKEN, { ...b, publicKeySpki: k }),
      w.deps,
    );
    assert.equal(res.status, 400);
    assert.equal((await res.json()).error, "badPublicKey");
  }
  assert.equal(w.store.devices.size, 0);
});

Deno.test("revoked then re-register with the same installId -> active, same deviceId, works again", async () => {
  const w = world();
  const installId = crypto.randomUUID();
  const first = await body(installId);
  const { deviceId } =
    await (await handle(registerReq(USER_TOKEN, first.body), w.deps)).json();
  const off = await deactivate(
    await signedRequest(
      "device-deactivate",
      deviceId,
      first.key.privateKey,
      "{}",
      {
        timestamp: T0,
      },
    ),
    w.deps,
  );
  assert.equal(off.status, 200);
  assert.equal(w.store.devices.get(deviceId)!.status, "revoked");
  const again = await body(installId);
  const res = await (await handle(registerReq(USER_TOKEN, again.body), w.deps))
    .json();
  assert.equal(res.deviceId, deviceId);
  assert.equal(w.store.devices.get(deviceId)!.status, "active");
  const hb = await heartbeat(
    await signedRequest(
      "device-heartbeat",
      deviceId,
      again.key.privateKey,
      HB,
      {
        timestamp: T0,
      },
    ),
    w.deps,
  );
  assert.equal(hb.status, 200);
});

Deno.test("bad body -> badRequest (400): installId, name length, missing fields, not JSON", async () => {
  const w = world();
  const b = (await body()).body;
  const bad = [
    { ...b, installId: "not-a-uuid" },
    { ...b, deviceName: "" },
    { ...b, deviceName: "   " },
    { ...b, deviceName: "ক".repeat(31) },
    { ...b, appVersion: undefined },
    { ...b, androidVersion: 14 },
    [],
  ];
  for (const x of bad) {
    const res = await handle(registerReq(USER_TOKEN, x), w.deps);
    assert.equal(res.status, 400, JSON.stringify(x).slice(0, 40));
  }
  const notJson = new Request("http://localhost/device-register", {
    method: "POST",
    headers: { Authorization: `Bearer ${USER_TOKEN}` },
    body: "{oops",
  });
  assert.equal((await handle(notJson, w.deps)).status, 400);
  // 30 Bangla characters is fine.
  const ok = await handle(
    registerReq(USER_TOKEN, { ...b, deviceName: "ক".repeat(30) }),
    w.deps,
  );
  assert.equal(ok.status, 200);
});

Deno.test("register: methods other than POST -> 405", async () => {
  const w = world();
  const res = await handle(
    new Request("http://localhost/device-register"),
    w.deps,
  );
  assert.equal(res.status, 405);
  assert.equal((await res.json()).error, "methodNotAllowed");
});
