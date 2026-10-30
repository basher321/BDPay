import assert from "node:assert/strict";
import {
  DEMO,
  demoDeps,
  depsFromEnv,
  FakeStore,
} from "../_shared/fake_store.ts";
import type { SmsRecord } from "../_shared/types.ts";

const record = (over: Partial<SmsRecord> = {}): Omit<SmsRecord, "id"> => ({
  merchantId: "m1",
  deviceId: "d1",
  walletId: null,
  sender: "bKash",
  body: "x",
  receivedAt: "2026-10-30T06:00:00.000Z",
  serverReceivedAt: "2026-10-30T06:00:01.000Z",
  simSlot: "sim1",
  dedupeHash: "h1",
  operator: "bkash",
  trxId: "ABC12345",
  amountPoisha: 100,
  payerNumber: null,
  status: "unmatched",
  rejectReason: null,
  parserVersion: 1,
  ...over,
});

Deno.test("insertSms: two racing inserts -> one created, both get the same row", async () => {
  const store = new FakeStore();
  const [a, b] = await Promise.all([
    store.insertSms(record()),
    store.insertSms(record()),
  ]);
  assert.equal([a.created, b.created].filter(Boolean).length, 1);
  assert.equal(a.sms.id, b.sms.id);
  assert.equal(store.sms.length, 1);
});

Deno.test("dedupe is per merchant", async () => {
  const store = new FakeStore();
  await store.insertSms(record());
  const other = await store.insertSms(record({ merchantId: "m2" }));
  assert.ok(other.created);
  assert.equal(await store.findSmsByDedupe("m3", "h1"), null);
  assert.equal((await store.findSmsByDedupe("m2", "h1"))?.merchantId, "m2");
});

Deno.test("wallets and devices are per merchant; returned rows are copies", async () => {
  const store = new FakeStore();
  store.addWallet({
    id: "w1",
    merchantId: "m1",
    operator: "bkash",
    walletNumber: "01700000000",
    accountType: "merchant",
    simSlot: "sim1",
    isActive: true,
  });
  assert.equal((await store.listActiveWallets("m2")).length, 0);
  const d = await store.createDevice({
    merchantId: "m1",
    name: "a",
    installId: "i1",
    publicKeySpki: "k",
    status: "active",
    appVersion: "1",
    androidVersion: "14",
    lastSeenAt: "2026-10-30T06:00:00.000Z",
  });
  assert.equal(await store.findDeviceByInstall("m2", "i1"), null);
  assert.equal(await store.countActiveDevices("m2"), 0);
  (await store.getDevice(d.id))!.status = "revoked";
  assert.equal((await store.getDevice(d.id))!.status, "active");
});

Deno.test("parser rules come from the store with their version", async () => {
  const rules = await new FakeStore().getParserRules();
  assert.equal(rules.version, 1);
  assert.ok(Array.isArray(rules.rules));
});

Deno.test("the Store has no delete method", () => {
  const names = Object.getOwnPropertyNames(FakeStore.prototype);
  assert.ok(!names.some((n) => /delete|remove|truncate|drop/i.test(n)));
});

Deno.test("depsFromEnv: BDPAY_FAKE_STORE=1 -> one demo world per worker; otherwise null", async () => {
  assert.equal(depsFromEnv(() => undefined), null);
  assert.equal(
    depsFromEnv((k) => (k === "BDPAY_FAKE_STORE" ? "0" : undefined)),
    null,
  );
  const a = depsFromEnv((k) => (k === "BDPAY_FAKE_STORE" ? "1" : undefined));
  const b = depsFromEnv((k) => (k === "BDPAY_FAKE_STORE" ? "1" : undefined));
  assert.ok(a !== null && a === b);
  assert.deepEqual(await a.users.verify(DEMO.userToken), {
    userId: DEMO.userId,
  });
  assert.deepEqual(await a.store.findMerchantForUser(DEMO.userId), {
    merchantId: DEMO.merchantId,
  });
  assert.equal(
    (await demoDeps().store.listActiveWallets(DEMO.merchantId)).length,
    1,
  );
});
