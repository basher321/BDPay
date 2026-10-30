import assert from "node:assert/strict";
import { handle } from "../_shared/deactivate.ts";
import { handle as ingest } from "../_shared/ingest.ts";
import { dedupeHash } from "../_shared/parser.ts";
import { signedRequest } from "./helpers/device_signer.ts";
import { addDevice, T0, world } from "./helpers/world.ts";

Deno.test("deactivate sets revoked, is audited; then ingest -> 403 deviceRevoked", async () => {
  const w = world();
  const { device, key } = await addDevice(w.store);
  const res = await handle(
    await signedRequest("device-deactivate", device.id, key.privateKey, "{}", {
      timestamp: T0,
    }),
    w.deps,
  );
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  assert.equal(w.store.devices.get(device.id)!.status, "revoked");
  const audit = w.store.audit.at(-1)!;
  assert.equal(audit.action, "device.deactivate");
  assert.equal(audit.actorType, "device");
  assert.equal(audit.entityId, device.id);

  const body = "You have received Tk 5.00 TrxID ABC12345";
  const items = [{
    localId: "l1",
    sender: "bKash",
    body,
    receivedAt: new Date(T0).toISOString(),
    simSlot: "sim1",
    dedupeHash: await dedupeHash("bKash", body),
  }];
  const after = await ingest(
    await signedRequest(
      "sms-ingest",
      device.id,
      key.privateKey,
      JSON.stringify({ items }),
      {
        timestamp: T0,
      },
    ),
    w.deps,
  );
  assert.equal(after.status, 403);
  assert.equal((await after.json()).error, "deviceRevoked");
  // A second deactivate is refused too (revoked devices can do nothing).
  const again = await handle(
    await signedRequest("device-deactivate", device.id, key.privateKey, "{}", {
      timestamp: T0,
    }),
    w.deps,
  );
  assert.equal(again.status, 403);
});

Deno.test("deactivate: body must be a JSON object; GET -> 405", async () => {
  const w = world();
  const { device, key } = await addDevice(w.store);
  const res = await handle(
    await signedRequest("device-deactivate", device.id, key.privateKey, "[]", {
      timestamp: T0,
    }),
    w.deps,
  );
  assert.equal(res.status, 400);
  assert.equal(w.store.devices.get(device.id)!.status, "active");
  assert.equal(
    (await handle(new Request("http://localhost/device-deactivate"), w.deps))
      .status,
    405,
  );
});
