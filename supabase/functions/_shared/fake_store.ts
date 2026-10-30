// Spec 08 in-memory Store for tests and BDPAY_FAKE_STORE=1 runs. Never deletes anything. It is the only
// non-test file that imports parser_rules.json; handlers get the rules through Store.getParserRules.

import { releaseFromEnv } from "./heartbeat.ts";
import { consoleLogger, type Deps } from "./http.ts";
import { NoopMatcher } from "./matcher.ts";
import { MemoryRateLimiter } from "./rate_limit.ts";
import { loadRules, rulesVersion } from "./parser.ts";
import rulesJson from "./parser_rules.json" with { type: "json" };
import {
  type DeviceUpdate,
  type NewDevice,
  type ParserRulesRow,
  type Store,
  StoreError,
} from "./store.ts";
import type { AuditEntry, Device, SmsRecord, Wallet } from "./types.ts";
import { FakeUserVerifier } from "./user_auth.ts";

export class FakeStore implements Store {
  /** Direct access for tests. */
  readonly devices = new Map<string, Device>();
  readonly sms: SmsRecord[] = [];
  readonly audit: AuditEntry[] = [];
  readonly wallets: Wallet[] = [];
  private readonly owners = new Map<string, string>();
  private readonly rules: ParserRulesRow;

  constructor(
    private readonly now: () => number = Date.now,
    rules: unknown = rulesJson,
  ) {
    this.rules = { version: rulesVersion(loadRules(rules)), rules };
  }

  addOwner(userId: string, merchantId: string): void {
    this.owners.set(userId, merchantId);
  }

  addWallet(wallet: Wallet): void {
    this.wallets.push({ ...wallet });
  }

  findMerchantForUser(userId: string) {
    const merchantId = this.owners.get(userId);
    return Promise.resolve(merchantId === undefined ? null : { merchantId });
  }

  countActiveDevices(merchantId: string) {
    let n = 0;
    for (const d of this.devices.values()) {
      if (d.merchantId === merchantId && d.status === "active") n++;
    }
    return Promise.resolve(n);
  }

  findDeviceByInstall(merchantId: string, installId: string) {
    for (const d of this.devices.values()) {
      if (d.merchantId === merchantId && d.installId === installId) {
        return Promise.resolve({ ...d });
      }
    }
    return Promise.resolve(null);
  }

  createDevice(fields: NewDevice) {
    const device: Device = {
      ...fields,
      id: crypto.randomUUID(),
      createdAt: new Date(this.now()).toISOString(),
    };
    this.devices.set(device.id, device);
    return Promise.resolve({ ...device });
  }

  updateDevice(deviceId: string, fields: DeviceUpdate) {
    const d = this.devices.get(deviceId);
    if (d === undefined) return Promise.reject(new StoreError("notFound"));
    Object.assign(d, fields);
    return Promise.resolve({ ...d });
  }

  getDevice(deviceId: string) {
    const d = this.devices.get(deviceId);
    return Promise.resolve(d === undefined ? null : { ...d });
  }

  getParserRules() {
    return Promise.resolve(this.rules);
  }

  listActiveWallets(merchantId: string) {
    return Promise.resolve(
      this.wallets.filter((w) => w.merchantId === merchantId && w.isActive)
        .map((w) => ({ ...w })),
    );
  }

  findSmsByDedupe(merchantId: string, dedupeHash: string) {
    const s = this.sms.find((x) =>
      x.merchantId === merchantId && x.dedupeHash === dedupeHash
    );
    return Promise.resolve(s === undefined ? null : { ...s });
  }

  /** The check and the insert run with no await between them, so racing calls cannot both insert. */
  insertSms(record: Omit<SmsRecord, "id">) {
    const existing = this.sms.find((x) =>
      x.merchantId === record.merchantId && x.dedupeHash === record.dedupeHash
    );
    if (existing !== undefined) {
      return Promise.resolve({ sms: { ...existing }, created: false });
    }
    const sms: SmsRecord = { ...record, id: crypto.randomUUID() };
    this.sms.push(sms);
    return Promise.resolve({ sms: { ...sms }, created: true });
  }

  writeAudit(entry: AuditEntry) {
    this.audit.push({ ...entry, data: { ...entry.data } });
    return Promise.resolve();
  }
}

/** Fixed demo data for BDPAY_FAKE_STORE=1 runs and the smoke script. Not secrets: they only work with FakeStore. */
export const DEMO = {
  userToken: "fake-user-token",
  userId: "user-demo",
  merchantId: "merchant-demo",
} as const;

export function demoStore(now: () => number = Date.now): FakeStore {
  const store = new FakeStore(now);
  store.addOwner(DEMO.userId, DEMO.merchantId);
  store.addWallet({
    id: "wallet-demo-bkash",
    merchantId: DEMO.merchantId,
    operator: "bkash",
    walletNumber: "01700000000",
    accountType: "merchant",
    simSlot: "sim1",
    isActive: true,
  });
  return store;
}

export function demoDeps(now: () => number = Date.now): Deps {
  return {
    store: demoStore(now),
    users: new FakeUserVerifier(new Map([[DEMO.userToken, DEMO.userId]])),
    matcher: new NoopMatcher(),
    now,
    log: consoleLogger,
    limiter: new MemoryRateLimiter(now),
  };
}

let local: Deps | null = null;

/** BDPAY_FAKE_STORE=1 -> one FakeStore per worker; otherwise null (index.ts answers 503 storeNotReady). */
export function depsFromEnv(
  get: (name: string) => string | undefined,
): Deps | null {
  if (get("BDPAY_FAKE_STORE") !== "1") return null;
  local ??= { ...demoDeps(), release: releaseFromEnv(get) };
  return local;
}
