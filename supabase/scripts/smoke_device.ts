// Spec 08 local smoke test (plan D80: in one Deno process with one FakeStore, not through functions serve).
// Registers a fake device with the FakeStore demo user token, sends one signed bKash SMS and prints the results.
// Prints only response JSON: never the key pair, the signature, the token or the SMS text.
//
// Run from the project root: deno run supabase/scripts/smoke_device.ts

import { DEMO, demoDeps } from "../functions/_shared/fake_store.ts";
import { handle as ingest } from "../functions/_shared/ingest.ts";
import { dedupeHash } from "../functions/_shared/parser.ts";
import { handle as register } from "../functions/_shared/register.ts";
import {
  newDeviceKey,
  signedRequest,
} from "../functions/tests/helpers/device_signer.ts";

const deps = demoDeps();
deps.log = () => {}; // keep the output to the results below

const key = await newDeviceKey();
const reg = await register(
  new Request("http://localhost/device-register", {
    method: "POST",
    headers: { Authorization: `Bearer ${DEMO.userToken}` },
    body: JSON.stringify({
      installId: crypto.randomUUID(),
      deviceName: "Smoke phone",
      publicKeySpki: key.publicKeySpki,
      appVersion: "0.0.0-smoke",
      androidVersion: "14",
    }),
  }),
  deps,
);
const registered = await reg.json();
console.log("device-register", reg.status, JSON.stringify(registered));
if (reg.status !== 200) Deno.exit(1);

const sender = "bKash";
const body =
  "You have received payment Tk 1,250.00 from 01712345678. Ref: ORD-101. Fee Tk 0.00. " +
  "Balance Tk 15,340.50. TrxID 9K48X7Z2 at 02/10/2026 18:25";
const items = [{
  localId: "smoke-1",
  sender,
  body,
  receivedAt: new Date().toISOString(),
  simSlot: "sim1",
  dedupeHash: await dedupeHash(sender, body),
}];
const res = await ingest(
  await signedRequest(
    "sms-ingest",
    registered.deviceId,
    key.privateKey,
    JSON.stringify({ items }),
  ),
  deps,
);
console.log("sms-ingest", res.status, JSON.stringify(await res.json()));
Deno.exit(res.status === 200 ? 0 : 1);
