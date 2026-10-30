import assert from "node:assert/strict";
import { handle as deactivate } from "../_shared/deactivate.ts";
import { handle, type ItemResult, REJECT_MESSAGES } from "../_shared/ingest.ts";
import { dedupeHash } from "../_shared/parser.ts";
import type { SimSlot, Wallet } from "../_shared/types.ts";
import { signedRequest } from "./helpers/device_signer.ts";
import { addDevice, MIN, T0, world } from "./helpers/world.ts";

const DAY = 24 * 60 * MIN;

const SAMPLES = {
  bkash: {
    sender: "bKash",
    body:
      "You have received payment Tk 1,250.00 from 01712345678. Ref: ORD-101. Fee Tk 0.00. " +
      "Balance Tk 15,340.50. TrxID 9K48X7Z2 at 02/10/2026 18:25",
    trxId: "9K48X7Z2",
    amountPoisha: 125000,
  },
  nagad: {
    sender: "NAGAD",
    body:
      "Money Received Amount: Tk 2,500.00 Sender: 01812345678 TxnID: 71B99AA2 Balance: Tk 15,000.00 " +
      "Time: 02/10/2026 14:15",
    trxId: "71B99AA2",
    amountPoisha: 250000,
  },
  rocket: {
    sender: "16216",
    body:
      "Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. " +
      "TxnId: 24010200123",
    trxId: "24010200123",
    amountPoisha: 150000,
  },
  upay: {
    sender: "upay",
    body:
      "You have received Tk 800.00 from 01711223344. Txn ID: 4UP82910. Current balance Tk 3,400.00. Fee Tk 0.00.",
    trxId: "4UP82910",
    amountPoisha: 80000,
  },
};

let n = 0;
async function item(
  sender: string,
  body: string,
  over: Partial<{ receivedAt: string; simSlot: SimSlot; dedupeHash: string }> =
    {},
) {
  return {
    localId: `local-${++n}`,
    sender,
    body,
    receivedAt: new Date(T0 - 2 * MIN).toISOString(),
    simSlot: "sim1" as SimSlot,
    dedupeHash: await dedupeHash(sender, body),
    ...over,
  };
}

async function setup() {
  const w = world();
  const { device, key } = await addDevice(w.store);
  const send = async (items: unknown[]) => {
    const res = await handle(
      await signedRequest(
        "sms-ingest",
        device.id,
        key.privateKey,
        JSON.stringify({ items }),
        { timestamp: w.clock.now },
      ),
      w.deps,
    );
    return { status: res.status, json: await res.json() };
  };
  return { w, device, key, send };
}

const wallet = (id: string, over: Partial<Wallet> = {}): Wallet => ({
  id,
  merchantId: "m1",
  operator: "bkash",
  walletNumber: "01700000000",
  accountType: "merchant",
  simSlot: "sim1",
  isActive: true,
  ...over,
});

Deno.test("each of the 4 operator samples is accepted with the right trxId and amountPoisha", async () => {
  const { w, send } = await setup();
  const items = await Promise.all(
    Object.values(SAMPLES).map((s) => item(s.sender, s.body)),
  );
  const { status, json } = await send(items);
  assert.equal(status, 200);
  assert.equal(json.ok, true);
  const results = json.results as ItemResult[];
  assert.deepEqual(results.map((r) => r.result), Array(4).fill("accepted"));
  assert.deepEqual(
    results.map((r) => r.verifyStatus),
    Array(4).fill("pending"),
  );
  assert.deepEqual(results.map((r) => r.localId), items.map((i) => i.localId));
  for (const [op, s] of Object.entries(SAMPLES)) {
    const row = w.store.sms.find((x) => x.operator === op)!;
    assert.equal(row.trxId, s.trxId, op);
    assert.equal(row.amountPoisha, s.amountPoisha, op);
    assert.equal(row.status, "unmatched", op);
    assert.equal(row.rejectReason, null, op);
    assert.equal(row.parserVersion, 1, op);
    assert.equal(row.merchantId, "m1", op);
  }
  assert.equal(w.matcher.calls.length, 4);
});

Deno.test("hashMismatch: not stored, smsId null, Bangla message", async () => {
  const { w, send } = await setup();
  const it = await item(SAMPLES.bkash.sender, SAMPLES.bkash.body, {
    dedupeHash: "0".repeat(64),
  });
  const { json } = await send([it]);
  assert.deepEqual(json.results[0], {
    localId: it.localId,
    smsId: null,
    result: "rejected",
    reason: "hashMismatch",
    verifyStatus: "rejected",
    serverMessage: "ডেটা মেলেনি — আবার পাঠান",
  });
  assert.equal(w.store.sms.length, 0);
});

Deno.test("edge: the same batch sent twice -> every item duplicate with the same smsId; nothing stored twice", async () => {
  const { w, send } = await setup();
  const items = [
    await item(SAMPLES.bkash.sender, SAMPLES.bkash.body),
    await item("bKash", "Your bKash OTP is 123456"),
  ];
  const first = (await send(items)).json.results as ItemResult[];
  const second = (await send(items)).json.results as ItemResult[];
  assert.equal(w.store.sms.length, 2);
  assert.deepEqual(second.map((r) => r.result), ["duplicate", "duplicate"]);
  assert.deepEqual(second.map((r) => r.smsId), first.map((r) => r.smsId));
  assert.equal(second[0].verifyStatus, "pending");
  assert.equal(second[1].verifyStatus, "rejected");
  assert.equal(second[1].reason, "blocked");
  assert.equal(second[1].serverMessage, REJECT_MESSAGES.blocked);
  assert.equal(w.matcher.calls.length, 1);
});

Deno.test("edge: two items with the same dedupeHash in one batch -> accepted, then duplicate", async () => {
  const { w, send } = await setup();
  const a = await item(SAMPLES.nagad.sender, SAMPLES.nagad.body);
  const b = { ...a, localId: "other-local" };
  const results = (await send([a, b])).json.results as ItemResult[];
  assert.equal(results[0].result, "accepted");
  assert.equal(results[1].result, "duplicate");
  assert.equal(results[1].localId, "other-local");
  assert.equal(results[1].smsId, results[0].smsId);
  assert.equal(w.store.sms.length, 1);
});

Deno.test("a duplicate of a matched SMS reports verified", async () => {
  const { w, send } = await setup();
  const it = await item(SAMPLES.upay.sender, SAMPLES.upay.body);
  await send([it]);
  w.store.sms[0].status = "matched";
  const r = (await send([it])).json.results[0] as ItemResult;
  assert.equal(r.result, "duplicate");
  assert.equal(r.verifyStatus, "verified");
});

Deno.test("senderNotTrusted: stored as rejected, never matched", async () => {
  const { w, send } = await setup();
  const r = (await send([
    await item(
      "01799999999",
      "You have received Tk 5,000.00 from 01711111111. TrxID FAKE1234",
    ),
  ])).json.results[0] as ItemResult;
  assert.equal(r.result, "rejected");
  assert.equal(r.reason, "senderNotTrusted");
  assert.equal(r.serverMessage, "প্রেরক বিশ্বস্ত নয়");
  assert.ok(r.smsId);
  const row = w.store.sms[0];
  assert.equal(row.status, "rejected");
  assert.equal(row.rejectReason, "senderNotTrusted");
  assert.equal(row.operator, null);
  assert.equal(row.trxId, null);
  assert.equal(w.matcher.calls.length, 0);
});

Deno.test("blocked: OTP from a buggy app stored with body null", async () => {
  const { w, send } = await setup();
  const r = (await send([
    await item("bKash", "Your bKash verification code is 482910"),
  ])).json
    .results[0] as ItemResult;
  assert.equal(r.reason, "blocked");
  assert.equal(r.serverMessage, "OTP/অফার — রাখা হয়নি");
  assert.equal(w.store.sms[0].body, null);
  assert.equal(w.store.sms[0].status, "rejected");
  assert.equal(w.matcher.calls.length, 0);
});

Deno.test("notIncoming, parseFailed (body kept), tooOld", async () => {
  const { w, send } = await setup();
  const results = (await send([
    await item(
      "bKash",
      "Send Money Tk 500.00 to 01711000000 successful. TrxID ABC12345",
    ),
    await item("bKash", "You have received money. TrxID ABC12345"),
    await item(SAMPLES.rocket.sender, SAMPLES.rocket.body, {
      receivedAt: new Date(T0 - 7 * DAY - 1000).toISOString(),
    }),
  ])).json.results as ItemResult[];
  assert.deepEqual(results.map((r) => r.reason), [
    "notIncoming",
    "parseFailed",
    "tooOld",
  ]);
  assert.deepEqual(results.map((r) => r.serverMessage), [
    "টাকা গ্রহণের এসএমএস নয়",
    "ফরম্যাট বোঝা যায়নি",
    "৭ দিনের বেশি পুরনো",
  ]);
  assert.ok(results.every((r) => r.verifyStatus === "rejected" && r.smsId));
  assert.equal(w.store.sms[1].body, "You have received money. TrxID ABC12345");
  assert.ok(w.store.sms.every((s) => s.status === "rejected"));
  assert.equal(w.matcher.calls.length, 0);
});

Deno.test("exactly 7 days old is still accepted", async () => {
  const { send } = await setup();
  const r = (await send([
    await item(SAMPLES.rocket.sender, SAMPLES.rocket.body, {
      receivedAt: new Date(T0 - 7 * DAY).toISOString(),
    }),
  ])).json.results[0] as ItemResult;
  assert.equal(r.result, "accepted");
});

Deno.test("edge: receivedAt in the future is clamped to server time, not rejected", async () => {
  const { w, send } = await setup();
  const r = (await send([
    await item(SAMPLES.bkash.sender, SAMPLES.bkash.body, {
      receivedAt: new Date(T0 + 60 * MIN).toISOString(),
    }),
  ])).json.results[0] as ItemResult;
  assert.equal(r.result, "accepted");
  assert.equal(w.store.sms[0].receivedAt, new Date(T0).toISOString());
  assert.equal(w.store.sms[0].serverReceivedAt, new Date(T0).toISOString());
});

Deno.test("wallet resolution: by simSlot, by single wallet, and null", async () => {
  const { w, send } = await setup();
  w.store.addWallet(wallet("bk-sim1", { simSlot: "sim1" }));
  w.store.addWallet(wallet("bk-sim2", { simSlot: "sim2" }));
  w.store.addWallet(wallet("ng-only", { operator: "nagad", simSlot: "sim1" }));
  w.store.addWallet(
    wallet("other-merchant", { merchantId: "m2", operator: "upay" }),
  );
  await send([
    await item(SAMPLES.bkash.sender, SAMPLES.bkash.body, { simSlot: "sim2" }),
    await item(SAMPLES.nagad.sender, SAMPLES.nagad.body, { simSlot: "sim2" }),
    await item(SAMPLES.upay.sender, SAMPLES.upay.body),
  ]);
  const walletOf = (op: string) =>
    w.store.sms.find((s) => s.operator === op)!.walletId;
  assert.equal(walletOf("bkash"), "bk-sim2");
  assert.equal(walletOf("nagad"), "ng-only");
  assert.equal(walletOf("upay"), null);
});

Deno.test("51 items -> 400; 0 items -> 400; bad shapes -> 400", async () => {
  const { w, send } = await setup();
  const one = await item(SAMPLES.bkash.sender, SAMPLES.bkash.body);
  const many = Array.from(
    { length: 51 },
    (_, i) => ({ ...one, localId: `l${i}` }),
  );
  for (
    const bad of [
      many,
      [],
      [{ ...one, simSlot: "sim3" }],
      [{ ...one, receivedAt: "yesterday" }],
      [{ ...one, body: 5 }],
      ["x"],
    ]
  ) {
    const { status, json } = await send(bad);
    assert.equal(status, 400);
    assert.equal(json.error, "badRequest");
  }
  assert.equal(w.store.sms.length, 0);
  // 50 is fine.
  const fifty = await Promise.all(
    Array.from(
      { length: 50 },
      (_, i) =>
        item(
          "bKash",
          `You have received Tk ${i + 1}.00 TrxID ABC1234${i % 10}X`,
        ),
    ),
  );
  assert.equal((await send(fifty)).status, 200);
});

Deno.test("body over 256 KB -> 413 (no Content-Length trusted)", async () => {
  const { w, device, key } = await setup();
  const big = JSON.stringify({ items: [], pad: "x".repeat(256 * 1024) });
  const req = await signedRequest(
    "sms-ingest",
    device.id,
    key.privateKey,
    big,
    {
      timestamp: T0,
    },
  );
  const res = await handle(req, w.deps);
  assert.equal(res.status, 413);
  assert.equal((await res.json()).error, "tooLarge");
  // A stream without Content-Length is cut off too.
  const stream = new ReadableStream({
    start(c) {
      for (let i = 0; i < 300; i++) c.enqueue(new Uint8Array(1024));
      c.close();
    },
  });
  const res2 = await handle(
    new Request("http://localhost/sms-ingest", {
      method: "POST",
      body: stream,
    }),
    w.deps,
  );
  assert.equal(res2.status, 413);
});

Deno.test("one bad item does not fail the others", async () => {
  const { w, send } = await setup();
  const results = (await send([
    await item(SAMPLES.bkash.sender, SAMPLES.bkash.body),
    await item(SAMPLES.nagad.sender, SAMPLES.nagad.body, {
      dedupeHash: "f".repeat(64),
    }),
    await item("bKash", "Your OTP is 123456"),
    await item(SAMPLES.upay.sender, SAMPLES.upay.body),
  ])).json.results as ItemResult[];
  assert.deepEqual(results.map((r) => r.result), [
    "accepted",
    "rejected",
    "rejected",
    "accepted",
  ]);
  assert.equal(w.store.sms.length, 3);
});

Deno.test("edge: a revoked device's old signed request replayed within 5 minutes -> deviceRevoked", async () => {
  const { w, device, key } = await setup();
  const body = JSON.stringify({
    items: [await item(SAMPLES.bkash.sender, SAMPLES.bkash.body)],
  });
  const old = await signedRequest(
    "sms-ingest",
    device.id,
    key.privateKey,
    body,
    {
      timestamp: T0,
    },
  );
  const off = await deactivate(
    await signedRequest("device-deactivate", device.id, key.privateKey, "{}", {
      timestamp: T0,
    }),
    w.deps,
  );
  assert.equal(off.status, 200);
  w.clock.now = T0 + 4 * MIN;
  const res = await handle(old, w.deps);
  assert.equal(res.status, 403);
  assert.equal((await res.json()).error, "deviceRevoked");
  assert.equal(w.store.sms.length, 0);
});

Deno.test("an unsigned or wrongly signed ingest stores nothing", async () => {
  const { w, device, key } = await setup();
  const body = JSON.stringify({
    items: [await item(SAMPLES.bkash.sender, SAMPLES.bkash.body)],
  });
  const unsigned = new Request("http://localhost/sms-ingest", {
    method: "POST",
    body,
  });
  assert.equal((await handle(unsigned, w.deps)).status, 401);
  const replay = await signedRequest(
    "sms-ingest",
    device.id,
    key.privateKey,
    body,
    {
      timestamp: T0,
      signAs: "device-heartbeat",
    },
  );
  assert.equal(
    (await (await handle(replay, w.deps)).json()).error,
    "badSignature",
  );
  assert.equal(w.store.sms.length, 0);
});

Deno.test("sms-ingest: methods other than POST -> 405", async () => {
  const { w } = await setup();
  const res = await handle(
    new Request("http://localhost/sms-ingest", { method: "PUT" }),
    w.deps,
  );
  assert.equal(res.status, 405);
});
