// Spec 09 local smoke test (plan 09 D30: one Deno process, one FakeStore - no server, no database).
// Creates a payment session, registers a fake device, sends a bKash SMS through sms-ingest, submits the TrxID
// through pay-session and prints the result. Prints only statuses and the pay link (a FakeStore token that works
// nowhere else) - never the key pair, signatures or the SMS text.
//
// Run from the project root: deno run supabase/scripts/smoke_match.ts

import { DEMO, demoDeps } from "../functions/_shared/fake_store.ts";
import { handle as ingest } from "../functions/_shared/ingest.ts";
import { dedupeHash } from "../functions/_shared/parser.ts";
import { handle as paySession } from "../functions/_shared/pay_session.ts";
import { handle as register } from "../functions/_shared/register.ts";
import { hashToken, newSessionToken } from "../functions/_shared/token.ts";
import {
  newDeviceKey,
  signedRequest,
} from "../functions/tests/helpers/device_signer.ts";
import type { FakeStore } from "../functions/_shared/fake_store.ts";

const deps = demoDeps();
deps.log = () => {};
const store = deps.store as FakeStore;
store.setMerchantName(DEMO.merchantId, "Smoke shop");

// 1. A payment session (what spec 10 creates from a Shopify order).
const token = newSessionToken();
await store.createPaymentSession({
  merchantId: DEMO.merchantId,
  storeId: "store-smoke",
  tokenHash: await hashToken(token),
  orderRef: "#SMOKE1",
  externalOrderId: null,
  amountPoisha: 125000,
  returnUrl: "https://example.com/orders/smoke",
  submitDeadline: new Date(Date.now() + 60 * 60_000).toISOString(),
});
console.log("pay link (local only):", `pay_page/index.html?t=${token}`);

// 2. A phone.
const key = await newDeviceKey();
const reg = await (await register(
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
)).json();
console.log("device registered:", reg.ok === true);

// 3. The bKash SMS arrives (Tk 1,250.00, TrxID SMOKE9X7).
const sender = "bKash";
const body =
  "You have received payment Tk 1,250.00 from 01700000001. Fee Tk 0.00. TrxID SMOKE9X7 at 30/10/2026 18:25";
const items = [{
  localId: "smoke-1",
  sender,
  body,
  receivedAt: new Date().toISOString(),
  simSlot: "sim1",
  dedupeHash: await dedupeHash(sender, body),
}];
const ing = await (await ingest(
  await signedRequest(
    "sms-ingest",
    reg.deviceId,
    key.privateKey,
    JSON.stringify({ items }),
  ),
  deps,
)).json();
console.log(
  "sms-ingest:",
  ing.results?.[0]?.result,
  ing.results?.[0]?.verifyStatus,
);

// 4. The customer submits the TrxID on the pay page.
const pay = await (await paySession(
  new Request("http://localhost/pay-session", {
    method: "POST",
    headers: { "x-forwarded-for": "127.0.0.1" },
    body: JSON.stringify({ token, operator: "bkash", trxId: "smoke9x7" }),
  }),
  deps,
)).json();
console.log("pay-session:", pay.result, pay.session?.status);
console.log(pay.session?.status === "verified" ? "verified" : "NOT verified");
