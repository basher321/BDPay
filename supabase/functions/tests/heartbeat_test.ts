import assert from "node:assert/strict";
import { handle, releaseFromEnv } from "../_shared/heartbeat.ts";
import { signedRequest } from "./helpers/device_signer.ts";
import { addDevice, MIN, T0, world } from "./helpers/world.ts";

const BODY = {
  appVersion: "1.2.0",
  smsPermission: true,
  batteryOptimizationOff: false,
  monitoring: true,
  queueCount: 3,
};

Deno.test("heartbeat updates lastSeenAt and appVersion; returns serverTime and rulesVersion", async () => {
  const w = world();
  const { device, key } = await addDevice(w.store);
  w.clock.now = T0 + 30 * MIN;
  const res = await handle(
    await signedRequest(
      "device-heartbeat",
      device.id,
      key.privateKey,
      JSON.stringify(BODY),
      {
        timestamp: w.clock.now,
      },
    ),
    w.deps,
  );
  assert.equal(res.status, 200);
  const nowIso = new Date(T0 + 30 * MIN).toISOString();
  assert.deepEqual(await res.json(), {
    ok: true,
    serverTime: nowIso,
    rulesVersion: 1,
  });
  const d = w.store.devices.get(device.id)!;
  assert.equal(d.lastSeenAt, nowIso);
  assert.equal(d.appVersion, "1.2.0");
  assert.equal(w.store.audit.at(-1)?.action, "device.heartbeat");
});

Deno.test("heartbeat: bad body -> 400, nothing changed", async () => {
  const w = world();
  const { device, key } = await addDevice(w.store);
  for (
    const bad of [
      { ...BODY, smsPermission: "yes" },
      { ...BODY, queueCount: -1 },
      { ...BODY, queueCount: 1.5 },
      { ...BODY, appVersion: "" },
      [],
    ]
  ) {
    const res = await handle(
      await signedRequest(
        "device-heartbeat",
        device.id,
        key.privateKey,
        JSON.stringify(bad),
        {
          timestamp: T0,
        },
      ),
      w.deps,
    );
    assert.equal(res.status, 400);
  }
  assert.equal(w.store.devices.get(device.id)!.appVersion, "1.0.0");
});

Deno.test("heartbeat: unsigned -> 401, GET -> 405", async () => {
  const w = world();
  const res = await handle(
    new Request("http://localhost/device-heartbeat", {
      method: "POST",
      body: JSON.stringify(BODY),
    }),
    w.deps,
  );
  assert.equal((await res.json()).error, "missingSignature");
  assert.equal(
    (await handle(new Request("http://localhost/device-heartbeat"), w.deps))
      .status,
    405,
  );
});

Deno.test("spec 15: heartbeat adds latestAppVersion and appDownloadUrl only when configured", async () => {
  const w = world();
  const { device, key } = await addDevice(w.store);
  const send = async () =>
    await (await handle(
      await signedRequest(
        "device-heartbeat",
        device.id,
        key.privateKey,
        JSON.stringify(BODY),
        {
          timestamp: w.clock.now,
        },
      ),
      w.deps,
    )).json();
  const without = await send();
  assert.ok(!("latestAppVersion" in without) && !("appDownloadUrl" in without));
  assert.equal(without.rulesVersion, 1);
  w.deps.release = {
    latestAppVersion: "1.2.0",
    appDownloadUrl: "https://pay.example.com/download.html",
  };
  const withRelease = await send();
  assert.equal(withRelease.latestAppVersion, "1.2.0");
  assert.equal(
    withRelease.appDownloadUrl,
    "https://pay.example.com/download.html",
  );
  assert.equal(withRelease.rulesVersion, 1);
});

Deno.test("spec 15: releaseFromEnv needs both values, a x.y.z version and an https URL", () => {
  const env = (v?: string, u?: string) => (k: string) =>
    k === "LATEST_APP_VERSION" ? v : k === "APP_DOWNLOAD_URL" ? u : undefined;
  assert.deepEqual(
    releaseFromEnv(env(" 1.0.1 ", "https://pay.example.com/download.html")),
    {
      latestAppVersion: "1.0.1",
      appDownloadUrl: "https://pay.example.com/download.html",
    },
  );
  for (
    const [v, u] of [
      [undefined, "https://pay.example.com/d"],
      ["1.0.1", undefined],
      ["1.0", "https://pay.example.com/d"],
      ["1.0.1-beta", "https://pay.example.com/d"],
      ["1.0.1", "http://pay.example.com/d"],
      ["1.0.1", "javascript:alert(1)"],
      ["1.0.1", "https://user:pw@pay.example.com/d"],
      ["1.0.1", "not a url"],
    ]
  ) {
    assert.equal(releaseFromEnv(env(v, u)), undefined, `${v} ${u}`);
  }
});
