// Spec 12a shared contract suite: the same tests for every Store implementation. Each test makes its own merchant
// and looks only at its own rows. A final test fails if any Store method was never called.
//
// Covers the Store methods that exist today (spec 08). Specs 09-11 add theirs here as they are built.

import assert from "node:assert/strict";
import { dedupeHash } from "../../_shared/parser.ts";
import {
  type NewPaymentSession,
  type Store,
  StoreError,
} from "../../_shared/store.ts";
import type { AuditEntry, SmsRecord } from "../../_shared/types.ts";
import { newDeviceKey } from "../helpers/device_signer.ts";
import { randomHex, type StoreMaker } from "./makers.ts";

/** Every Store method. `satisfies` makes the compiler fail if one is added to Store and missing here. */
const STORE_METHODS = {
  findMerchantForUser: true,
  countActiveDevices: true,
  findDeviceByInstall: true,
  createDevice: true,
  updateDevice: true,
  getDevice: true,
  getParserRules: true,
  listActiveWallets: true,
  findSmsByDedupe: true,
  insertSms: true,
  writeAudit: true,
  createPaymentSession: true,
  getSessionByTokenHash: true,
  getSession: true,
  getClaim: true,
  getSms: true,
  getMerchantName: true,
  hasDeviceSeenSince: true,
  findLiveClaimByTrx: true,
  spendAttempt: true,
  submitClaim: true,
  findUnmatchedSms: true,
  findPendingClaimByTrx: true,
  recordVerified: true,
  recordMismatch: true,
  recordRejected: true,
  findMismatchClaimBySms: true,
  getSmsResults: true,
  expireDue: true,
  hitRateLimit: true,
} as const satisfies Record<keyof Store, true>;

const ISO_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

/** Wraps the store so the suite can check every method was called at least once. */
function tracked(store: Store, called: Set<string>): Store {
  return new Proxy(store, {
    get(target, prop, receiver) {
      const value = Reflect.get(target, prop, receiver);
      if (typeof value === "function" && prop in STORE_METHODS) {
        called.add(String(prop));
        return value.bind(target);
      }
      return value;
    },
  });
}

async function newDeviceFields(merchantId: string) {
  return {
    merchantId,
    name: "Contract phone",
    installId: crypto.randomUUID(),
    publicKeySpki: (await newDeviceKey()).publicKeySpki,
    status: "active" as const,
    appVersion: "1.0.0",
    androidVersion: "14",
    lastSeenAt: new Date().toISOString(),
  };
}

async function smsFields(
  merchantId: string,
  deviceId: string,
  over: Partial<SmsRecord> = {},
): Promise<Omit<SmsRecord, "id">> {
  const body = `You have received Tk 10.00. TrxID C${
    randomHex(5).toUpperCase()
  }`;
  return {
    merchantId,
    deviceId,
    walletId: null,
    sender: "bKash",
    body,
    receivedAt: new Date().toISOString(),
    serverReceivedAt: new Date().toISOString(),
    simSlot: "sim1",
    dedupeHash: await dedupeHash("bKash", body),
    operator: "bkash",
    trxId: `C${randomHex(5).toUpperCase()}`,
    amountPoisha: 1000,
    payerNumber: null,
    status: "unmatched",
    rejectReason: null,
    parserVersion: 1,
    ...over,
  };
}

/**
 * Registers the contract tests for one Store implementation. getMaker is called once (lazily), so an ignored
 * suite never connects to anything.
 */
export function runContract(
  label: string,
  getMaker: () => Promise<StoreMaker>,
  ignore = false,
): void {
  const called = new Set<string>();
  let cached: Promise<{ maker: StoreMaker; store: Store }> | null = null;
  const setup = () => {
    cached ??= getMaker().then((maker) => ({
      maker,
      store: tracked(maker.store, called),
    }));
    return cached;
  };
  const test = (name: string, fn: () => Promise<void>) =>
    Deno.test({ name: `[${label}] ${name}`, ignore, fn });

  test("merchant: findMerchantForUser finds the owner; an unknown user -> null", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    assert.deepEqual(await store.findMerchantForUser(m.userId), {
      merchantId: m.merchantId,
    });
    assert.equal(await store.findMerchantForUser(crypto.randomUUID()), null);
  });

  test("devices: create returns the full record; get and findDeviceByInstall return it", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const fields = await newDeviceFields(m.merchantId);
    const d = await store.createDevice(fields);
    assert.match(d.id, /^[0-9a-f-]{36}$/);
    assert.match(d.createdAt, ISO_UTC);
    assert.deepEqual({ ...d, id: undefined, createdAt: undefined }, {
      ...fields,
      id: undefined,
      createdAt: undefined,
    });
    assert.deepEqual(await store.getDevice(d.id), d);
    assert.deepEqual(
      await store.findDeviceByInstall(m.merchantId, fields.installId),
      d,
    );
  });

  test("devices: updateDevice changes only the given fields; unknown id -> StoreError notFound", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const d = await store.createDevice(await newDeviceFields(m.merchantId));
    const seen = new Date(Date.now() + 60_000).toISOString();
    const u = await store.updateDevice(d.id, {
      appVersion: "2.0.0",
      lastSeenAt: seen,
    });
    assert.deepEqual(u, { ...d, appVersion: "2.0.0", lastSeenAt: seen });
    assert.deepEqual(await store.getDevice(d.id), u);
    await assert.rejects(
      () => store.updateDevice(crypto.randomUUID(), { appVersion: "x" }),
      (e: unknown) => e instanceof StoreError && e.code === "notFound",
    );
    assert.equal(await store.getDevice(crypto.randomUUID()), null);
  });

  test("devices: countActiveDevices counts only active devices of that merchant", async () => {
    const { maker, store } = await setup();
    const a = await maker.newMerchant();
    const b = await maker.newMerchant();
    await store.createDevice(await newDeviceFields(a.merchantId));
    const second = await store.createDevice(
      await newDeviceFields(a.merchantId),
    );
    await store.createDevice(await newDeviceFields(b.merchantId));
    assert.equal(await store.countActiveDevices(a.merchantId), 2);
    await store.updateDevice(second.id, { status: "revoked" });
    assert.equal(await store.countActiveDevices(a.merchantId), 1);
    assert.equal(await store.countActiveDevices(b.merchantId), 1);
  });

  test("rules: getParserRules returns the active rules, version 1, 4 operators", async () => {
    const { store } = await setup();
    const rules = await store.getParserRules();
    assert.equal(rules.version, 1);
    assert.ok(Array.isArray(rules.rules));
    assert.deepEqual(
      (rules.rules as { operator: string }[]).map((r) => r.operator),
      ["bkash", "nagad", "rocket", "upay"],
    );
  });

  test("wallets: listActiveWallets returns only active wallets of that merchant", async () => {
    const { maker, store } = await setup();
    const a = await maker.newMerchant();
    const b = await maker.newMerchant();
    const w1 = await maker.addWallet(a.merchantId, { simSlot: "sim1" });
    await maker.addWallet(a.merchantId, { operator: "nagad", isActive: false });
    await maker.addWallet(b.merchantId);
    assert.deepEqual(await store.listActiveWallets(a.merchantId), [w1]);
  });

  test("sms: insertSms new -> created true; same hash -> created false with the same row", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const d = await store.createDevice(await newDeviceFields(m.merchantId));
    const rec = await smsFields(m.merchantId, d.id);
    const first = await store.insertSms(rec);
    assert.equal(first.created, true);
    assert.deepEqual({ ...first.sms, id: undefined }, {
      ...rec,
      id: undefined,
    });
    const second = await store.insertSms({ ...rec, body: "other body" });
    assert.equal(second.created, false);
    assert.deepEqual(second.sms, first.sms);
    assert.deepEqual(
      await store.findSmsByDedupe(m.merchantId, rec.dedupeHash),
      first.sms,
    );
  });

  test("sms: dedupe is per merchant; findSmsByDedupe with another merchant -> null", async () => {
    const { maker, store } = await setup();
    const a = await maker.newMerchant();
    const b = await maker.newMerchant();
    const da = await store.createDevice(await newDeviceFields(a.merchantId));
    const db = await store.createDevice(await newDeviceFields(b.merchantId));
    const rec = await smsFields(a.merchantId, da.id);
    await store.insertSms(rec);
    assert.equal(
      await store.findSmsByDedupe(b.merchantId, rec.dedupeHash),
      null,
    );
    const other = await store.insertSms({
      ...rec,
      merchantId: b.merchantId,
      deviceId: db.id,
    });
    assert.equal(other.created, true);
  });

  test("sms: a rejected blocked row keeps body null and its reason", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const d = await store.createDevice(await newDeviceFields(m.merchantId));
    const rec = await smsFields(m.merchantId, d.id, {
      body: null,
      status: "rejected",
      rejectReason: "blocked",
      trxId: null,
      amountPoisha: null,
    });
    const { sms } = await store.insertSms(rec);
    assert.equal(sms.body, null);
    assert.equal(sms.rejectReason, "blocked");
  });

  test("race: insertSms with the same hash from 5 parallel calls -> one row, four created false", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const d = await store.createDevice(await newDeviceFields(m.merchantId));
    const rec = await smsFields(m.merchantId, d.id);
    const results = await Promise.all(
      Array.from({ length: 5 }, () => store.insertSms(rec)),
    );
    assert.equal(results.filter((r) => r.created).length, 1);
    assert.equal(new Set(results.map((r) => r.sms.id)).size, 1);
  });

  test("audit: writeAudit stores the entry for that merchant", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const entry: AuditEntry = {
      merchantId: m.merchantId,
      actorType: "device",
      actorId: crypto.randomUUID(),
      action: "device.deactivate",
      entity: "device",
      entityId: crypto.randomUUID(),
      data: { reRegistered: false, n: 1, note: null },
    };
    await store.writeAudit(entry);
    assert.deepEqual(await maker.readAudit(m.merchantId), [entry]);
  });

  test("isolation: every method with a merchantId returns nothing for another merchant", async () => {
    const { maker, store } = await setup();
    const a = await maker.newMerchant();
    const b = await maker.newMerchant();
    const fields = await newDeviceFields(a.merchantId);
    const d = await store.createDevice(fields);
    await maker.addWallet(a.merchantId);
    const rec = await smsFields(a.merchantId, d.id);
    await store.insertSms(rec);
    assert.equal(
      await store.findDeviceByInstall(b.merchantId, fields.installId),
      null,
    );
    assert.equal(await store.countActiveDevices(b.merchantId), 0);
    assert.deepEqual(await store.listActiveWallets(b.merchantId), []);
    assert.equal(
      await store.findSmsByDedupe(b.merchantId, rec.dedupeHash),
      null,
    );
    assert.deepEqual(await maker.readAudit(b.merchantId), []);
  });

  // ---- Spec 09: sessions, claims, matches ----

  async function newSession(
    store: Store,
    maker: StoreMaker,
    merchantId: string,
    over: Partial<NewPaymentSession> = {},
  ) {
    return await store.createPaymentSession({
      merchantId,
      storeId: await maker.newStoreId(merchantId),
      tokenHash: randomHex(32),
      orderRef: `#${randomHex(3)}`,
      externalOrderId: null,
      amountPoisha: 125000,
      returnUrl: "https://example.com/orders/1",
      submitDeadline: new Date(Date.now() + 60 * 60_000).toISOString(),
      ...over,
    });
  }

  const trx = (p: string) => `${p}${randomHex(5).toUpperCase()}`;

  test("sessions: create (open, 5 attempts); get by id and by token hash; merchant name", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const s = await newSession(store, maker, m.merchantId);
    assert.equal(s.status, "open");
    assert.equal(s.attemptsLeft, 5);
    assert.equal(s.activeClaimId, null);
    assert.match(s.createdAt, ISO_UTC);
    assert.deepEqual(await store.getSession(s.id), s);
    assert.deepEqual(await store.getSessionByTokenHash(s.tokenHash), s);
    assert.equal(await store.getSessionByTokenHash(randomHex(32)), null);
    assert.equal(await store.getMerchantName(m.merchantId), m.businessName);
  });

  test("claims: submit -> pending, attempts 4; a second TrxID supersedes the first; live / pending lookups", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const s = await newSession(store, maker, m.merchantId);
    const trx1 = trx("A");
    const trx2 = trx("B");
    const r1 = await store.submitClaim({
      sessionId: s.id,
      operator: "bkash",
      trxId: trx1,
    });
    assert.ok("claim" in r1);
    assert.equal(r1.claim.status, "pending");
    assert.equal(r1.claim.trxId, trx1);
    const after1 = (await store.getSession(s.id))!;
    assert.equal(after1.status, "pending");
    assert.equal(after1.attemptsLeft, 4);
    assert.equal(after1.activeClaimId, r1.claim.id);
    assert.deepEqual(
      await store.findLiveClaimByTrx(m.merchantId, "bkash", trx1),
      r1.claim,
    );
    assert.deepEqual(
      await store.findPendingClaimByTrx(m.merchantId, "bkash", trx1),
      r1.claim,
    );
    const r2 = await store.submitClaim({
      sessionId: s.id,
      operator: "bkash",
      trxId: trx2,
    });
    assert.ok("claim" in r2);
    assert.equal((await store.getClaim(r1.claim.id))!.status, "superseded");
    assert.equal((await store.getSession(s.id))!.attemptsLeft, 3);
    assert.equal(
      await store.findLiveClaimByTrx(m.merchantId, "bkash", trx1),
      null,
    );
    // The live TrxID cannot be claimed by another session of the same merchant.
    const other = await newSession(store, maker, m.merchantId);
    assert.deepEqual(
      await store.submitClaim({
        sessionId: other.id,
        operator: "bkash",
        trxId: trx2,
      }),
      { conflict: "alreadyUsed" },
    );
    assert.equal(await store.spendAttempt(other.id), 4);
    assert.equal((await store.getSession(other.id))!.status, "open");
  });

  test("claims: no attempts left -> noAttemptsLeft; past the deadline -> closed", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const s = await newSession(store, maker, m.merchantId);
    for (let i = 0; i < 5; i++) await store.spendAttempt(s.id);
    assert.equal(await store.spendAttempt(s.id), 0);
    assert.deepEqual(
      await store.submitClaim({
        sessionId: s.id,
        operator: "bkash",
        trxId: trx("N"),
      }),
      { conflict: "noAttemptsLeft" },
    );
    const late = await newSession(store, maker, m.merchantId, {
      submitDeadline: new Date(Date.now() - 60_000).toISOString(),
    });
    assert.deepEqual(
      await store.submitClaim({
        sessionId: late.id,
        operator: "bkash",
        trxId: trx("L"),
      }),
      { conflict: "closed" },
    );
  });

  test("recordVerified: one transaction; paying again with the same SMS or claim -> conflict", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const d = await store.createDevice(await newDeviceFields(m.merchantId));
    const s = await newSession(store, maker, m.merchantId);
    const rec = await smsFields(m.merchantId, d.id, { amountPoisha: 125000 });
    const { sms } = await store.insertSms(rec);
    assert.deepEqual(await store.getSms(sms.id), sms);
    assert.deepEqual(
      await store.findUnmatchedSms(m.merchantId, "bkash", rec.trxId!),
      sms,
    );
    const r = await store.submitClaim({
      sessionId: s.id,
      operator: "bkash",
      trxId: rec.trxId!,
    });
    assert.ok("claim" in r);
    const input = {
      claimId: r.claim.id,
      smsId: sms.id,
      method: "auto" as const,
      userId: null,
      note: null,
    };
    assert.equal(await store.recordVerified(input), "ok");
    assert.equal(await store.recordVerified(input), "conflict");
    const vs = (await store.getSession(s.id))!;
    assert.equal(vs.status, "verified");
    assert.match(vs.verifiedAt!, ISO_UTC);
    assert.equal((await store.getClaim(r.claim.id))!.status, "verified");
    assert.equal((await store.getSms(sms.id))!.status, "matched");
    assert.equal(
      await store.findUnmatchedSms(m.merchantId, "bkash", rec.trxId!),
      null,
    );
    const [res] = await store.getSmsResults(m.merchantId, [sms.id]);
    assert.equal(res.match?.method, "auto");
    assert.equal(res.claim?.id, r.claim.id);
    assert.equal(res.session?.id, s.id);
  });

  test("mismatch -> reject; findMismatchClaimBySms; guarded writes refuse stale changes", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const d = await store.createDevice(await newDeviceFields(m.merchantId));
    const s = await newSession(store, maker, m.merchantId);
    const rec = await smsFields(m.merchantId, d.id, { amountPoisha: 43000 });
    const { sms } = await store.insertSms(rec);
    const r = await store.submitClaim({
      sessionId: s.id,
      operator: "bkash",
      trxId: rec.trxId!,
    });
    assert.ok("claim" in r);
    const mm = { claimId: r.claim.id, smsId: sms.id, reason: "amount" };
    assert.equal(await store.recordMismatch(mm), "ok");
    assert.equal(await store.recordMismatch(mm), "conflict");
    const mc = (await store.findMismatchClaimBySms(sms.id))!;
    assert.equal(mc.id, r.claim.id);
    assert.equal(mc.candidateSmsId, sms.id);
    assert.equal((await store.getSession(s.id))!.status, "mismatch");
    const rj = { claimId: r.claim.id, userId: m.userId, note: null };
    assert.equal(await store.recordRejected(rj), "ok");
    assert.equal(await store.recordRejected(rj), "conflict");
    assert.equal((await store.getSession(s.id))!.status, "rejected");
    assert.equal(await store.findMismatchClaimBySms(sms.id), null);
    const [res] = await store.getSmsResults(m.merchantId, [sms.id]);
    assert.equal(res.claim?.status, "rejected");
    assert.equal(res.match, null);
  });

  test("expireDue: open past deadline -> expired; pending claim past 24 h -> expired", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    const late = await newSession(store, maker, m.merchantId, {
      submitDeadline: new Date(Date.now() - 60_000).toISOString(),
    });
    const waiting = await newSession(store, maker, m.merchantId);
    const r = await store.submitClaim({
      sessionId: waiting.id,
      operator: "bkash",
      trxId: trx("W"),
    });
    assert.ok("claim" in r);
    const counts = await store.expireDue(
      new Date(Date.now() + 25 * 60 * 60_000).toISOString(),
    );
    assert.ok(counts.sessions >= 2 && counts.claims >= 1);
    assert.equal((await store.getSession(late.id))!.status, "expired");
    assert.equal((await store.getSession(waiting.id))!.status, "expired");
    assert.equal((await store.getClaim(r.claim.id))!.status, "expired");
  });

  test("devices seen since; rate limit allows up to the limit in one window", async () => {
    const { maker, store } = await setup();
    const m = await maker.newMerchant();
    await store.createDevice(await newDeviceFields(m.merchantId));
    const ago = new Date(Date.now() - 60_000).toISOString();
    const ahead = new Date(Date.now() + 60_000).toISOString();
    assert.equal(await store.hasDeviceSeenSince(m.merchantId, ago), true);
    assert.equal(await store.hasDeviceSeenSince(m.merchantId, ahead), false);
    const key = `contract:${randomHex(8)}`;
    assert.equal(await store.hitRateLimit(key, 2, 3600), true);
    assert.equal(await store.hitRateLimit(key, 2, 3600), true);
    assert.equal(await store.hitRateLimit(key, 2, 3600), false);
  });

  test("coverage: every Store method was called by the suite", () => {
    const missing = Object.keys(STORE_METHODS).filter((k) => !called.has(k));
    assert.deepEqual(missing, []);
    return Promise.resolve();
  });
}
