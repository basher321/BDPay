// Spec 13a cross-check: the request signed by the Kotlin JVM test (like Android: P-256, SHA256withECDSA, DER)
// verifies with the server's device_auth.ts. The fixture is imported as JSON, so no read permission is needed.
import assert from "node:assert/strict";
import { utf8 } from "../_shared/crypto.ts";
import { checkDeviceRequest } from "../_shared/device_auth.ts";
import { FakeStore } from "../_shared/fake_store.ts";
import fixture from "./fixtures/android_signature.json" with { type: "json" };

async function setup() {
  const store = new FakeStore(() => Number(fixture.timestamp));
  const device = await store.createDevice({
    merchantId: "m1",
    name: "Android",
    installId: crypto.randomUUID(),
    publicKeySpki: fixture.publicKeySpki,
    status: "active",
    appVersion: "1.0.0",
    androidVersion: "14",
    lastSeenAt: new Date(Number(fixture.timestamp)).toISOString(),
  });
  const headers = (signature = fixture.signature) =>
    new Headers({
      "X-Device-Id": device.id,
      "X-Timestamp": fixture.timestamp,
      "X-Signature": signature,
    });
  return { store, headers };
}

Deno.test("the Kotlin-signed sms-ingest request verifies with device_auth.ts", async () => {
  const { store, headers } = await setup();
  const r = await checkDeviceRequest(
    fixture.functionName,
    headers(),
    utf8(fixture.body),
    store,
    Number(fixture.timestamp),
  );
  assert.ok(r.ok);
});

Deno.test("the same signature fails on another function, another body or another time", async () => {
  const { store, headers } = await setup();
  const now = Number(fixture.timestamp);
  const code = (r: Awaited<ReturnType<typeof checkDeviceRequest>>) =>
    r.ok ? "ok" : r.code;
  assert.equal(
    code(
      await checkDeviceRequest(
        "device-heartbeat",
        headers(),
        utf8(fixture.body),
        store,
        now,
      ),
    ),
    "badSignature",
  );
  assert.equal(
    code(
      await checkDeviceRequest(
        fixture.functionName,
        headers(),
        utf8(fixture.body + " "),
        store,
        now,
      ),
    ),
    "badSignature",
  );
  const moved = headers();
  moved.set("X-Timestamp", String(now + 1));
  assert.equal(
    code(
      await checkDeviceRequest(
        fixture.functionName,
        moved,
        utf8(fixture.body),
        store,
        now,
      ),
    ),
    "badSignature",
  );
});

Deno.test("the fixture is DER and holds no private key", () => {
  const sig = atob(fixture.signature);
  assert.equal(sig.charCodeAt(0), 0x30);
  assert.ok(!JSON.stringify(fixture).toLowerCase().includes("private"));
});
