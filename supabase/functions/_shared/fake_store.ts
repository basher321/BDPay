// Spec 08 in-memory Store for tests and BDPAY_FAKE_STORE=1 runs. Never deletes anything. It is the only
// non-test file that imports parser_rules.json; handlers get the rules through Store.getParserRules.

import { releaseFromEnv } from "./heartbeat.ts";
import { consoleLogger, type Deps } from "./http.ts";
import { StoreMatcher } from "./matcher.ts";
import { NoopNotifier } from "./notifier.ts";
import { storeLimiter } from "./rate_limit.ts";
import { loadRules, rulesVersion } from "./parser.ts";
import rulesJson from "./parser_rules.json" with { type: "json" };
import {
  type ConnectionUpdate,
  type DeviceUpdate,
  type NewApiConnection,
  type NewDevice,
  type NewPaymentSession,
  type OrderSyncUpdate,
  type ParserRulesRow,
  type SmsResult,
  type Store,
  StoreError,
} from "./store.ts";
import type {
  AuditEntry,
  ConnectionRecord,
  Device,
  Match,
  MatchMethod,
  Operator,
  OrderSync,
  PaymentClaim,
  PaymentSession,
  SmsRecord,
  Wallet,
} from "./types.ts";

/** Spec 09: a claim waits at most 24 hours for its SMS. */
export const MATCH_WINDOW_MS = 24 * 60 * 60 * 1000;
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
  // ---- Spec 09 ----
  // Every multi-record write checks everything and writes everything in one synchronous block (no await inside),
  // so racing callers cannot both succeed - the FakeStore's stand-in for one database transaction (plan 09 §3).

  readonly sessions = new Map<string, PaymentSession>();
  readonly claims = new Map<string, PaymentClaim>();
  readonly matches: Match[] = [];
  readonly merchantNames = new Map<string, string>();
  private readonly rateCounts = new Map<string, number>();
  /** Test-only: read methods of the matching flow await this, so a test can hold two callers after their reads. */
  gate: Promise<void> | null = null;

  private iso(ms = this.now()): string {
    return new Date(ms).toISOString();
  }

  private async pass(): Promise<void> {
    if (this.gate !== null) await this.gate;
  }

  setMerchantName(merchantId: string, name: string): void {
    this.merchantNames.set(merchantId, name);
  }

  createPaymentSession(fields: NewPaymentSession) {
    if (fields.externalOrderId !== null) {
      for (const s of this.sessions.values()) {
        if (
          s.storeId === fields.storeId &&
          s.externalOrderId === fields.externalOrderId
        ) {
          return Promise.reject(new StoreError("conflict"));
        }
      }
    }
    const session: PaymentSession = {
      ...fields,
      id: crypto.randomUUID(),
      status: "open",
      attemptsLeft: 5,
      activeClaimId: null,
      createdAt: this.iso(),
      verifiedAt: null,
    };
    this.sessions.set(session.id, session);
    return Promise.resolve({ ...session });
  }

  getSessionByTokenHash(tokenHash: string) {
    for (const s of this.sessions.values()) {
      if (s.tokenHash === tokenHash) return Promise.resolve({ ...s });
    }
    return Promise.resolve(null);
  }

  getSession(id: string) {
    const s = this.sessions.get(id);
    return Promise.resolve(s === undefined ? null : { ...s });
  }

  getClaim(id: string) {
    const c = this.claims.get(id);
    return Promise.resolve(c === undefined ? null : { ...c });
  }

  getSms(id: string) {
    const s = this.sms.find((x) => x.id === id);
    return Promise.resolve(s === undefined ? null : { ...s });
  }

  getMerchantName(merchantId: string) {
    return Promise.resolve(this.merchantNames.get(merchantId) ?? "");
  }

  hasDeviceSeenSince(merchantId: string, sinceIso: string) {
    const since = Date.parse(sinceIso);
    for (const d of this.devices.values()) {
      if (
        d.merchantId === merchantId && d.status === "active" &&
        Date.parse(d.lastSeenAt) >= since
      ) return Promise.resolve(true);
    }
    return Promise.resolve(false);
  }

  private liveClaim(merchantId: string, operator: Operator, trxId: string) {
    for (const c of this.claims.values()) {
      if (
        c.merchantId === merchantId && c.operator === operator &&
        c.trxId === trxId &&
        (c.status === "pending" || c.status === "verified" ||
          c.status === "mismatch")
      ) return c;
    }
    return null;
  }

  findLiveClaimByTrx(
    merchantId: string,
    operator: Operator,
    trxId: string,
  ) {
    const c = this.liveClaim(merchantId, operator, trxId);
    return Promise.resolve(c === null ? null : { ...c });
  }

  spendAttempt(sessionId: string) {
    const s = this.sessions.get(sessionId);
    if (s === undefined) return Promise.reject(new StoreError("notFound"));
    s.attemptsLeft = Math.max(0, s.attemptsLeft - 1);
    return Promise.resolve(s.attemptsLeft);
  }

  submitClaim(input: { sessionId: string; operator: Operator; trxId: string }) {
    // One block: check, build, write.
    const now = this.now();
    const s = this.sessions.get(input.sessionId);
    const open = s !== undefined &&
      (s.status === "pending" ||
        (s.status === "open" && now <= Date.parse(s.submitDeadline)));
    if (s === undefined || !open) {
      return Promise.resolve({ conflict: "closed" as const });
    }
    if (s.attemptsLeft <= 0) {
      return Promise.resolve({ conflict: "noAttemptsLeft" as const });
    }
    if (this.liveClaim(s.merchantId, input.operator, input.trxId) !== null) {
      return Promise.resolve({ conflict: "alreadyUsed" as const });
    }
    const old = s.activeClaimId === null
      ? undefined
      : this.claims.get(s.activeClaimId);
    const claim: PaymentClaim = {
      id: crypto.randomUUID(),
      merchantId: s.merchantId,
      sessionId: s.id,
      operator: input.operator,
      trxId: input.trxId,
      status: "pending",
      reason: null,
      candidateSmsId: null,
      matchDeadline: this.iso(now + MATCH_WINDOW_MS),
      createdAt: this.iso(now),
    };
    if (old !== undefined && old.status === "pending") {
      old.status = "superseded";
    }
    this.claims.set(claim.id, claim);
    s.attemptsLeft -= 1;
    s.status = "pending";
    s.activeClaimId = claim.id;
    return Promise.resolve({ claim: { ...claim } });
  }

  async findUnmatchedSms(
    merchantId: string,
    operator: Operator,
    trxId: string,
  ) {
    await this.pass();
    const s = this.sms.find((x) =>
      x.merchantId === merchantId && x.operator === operator &&
      x.trxId === trxId && x.status === "unmatched"
    );
    return s === undefined ? null : { ...s };
  }

  async findPendingClaimByTrx(
    merchantId: string,
    operator: Operator,
    trxId: string,
  ) {
    await this.pass();
    for (const c of this.claims.values()) {
      if (
        c.merchantId === merchantId && c.operator === operator &&
        c.trxId === trxId && c.status === "pending"
      ) return { ...c };
    }
    return null;
  }

  recordVerified(input: {
    claimId: string;
    smsId: string;
    method: MatchMethod;
    userId: string | null;
    note: string | null;
  }) {
    const c = this.claims.get(input.claimId);
    const sms = this.sms.find((x) => x.id === input.smsId);
    const s = c === undefined ? undefined : this.sessions.get(c.sessionId);
    const ok = c !== undefined && sms !== undefined && s !== undefined &&
      s.activeClaimId === c.id &&
      (input.method === "auto"
        ? c.status === "pending" && s.status === "pending"
        : c.status === "mismatch" && s.status === "mismatch" &&
          c.candidateSmsId === sms.id) &&
      sms.status === "unmatched" && sms.merchantId === c.merchantId &&
      sms.operator === c.operator && sms.trxId === c.trxId &&
      !this.matches.some((m) => m.claimId === c.id || m.smsId === sms.id);
    if (!ok) return Promise.resolve("conflict" as const);
    const now = this.iso();
    this.matches.push({
      id: crypto.randomUUID(),
      merchantId: c.merchantId,
      claimId: c.id,
      smsId: sms.id,
      method: input.method,
      userId: input.userId,
      note: input.note,
      createdAt: now,
    });
    c.status = "verified";
    c.candidateSmsId = sms.id;
    s.status = "verified";
    s.verifiedAt = now;
    sms.status = "matched";
    return Promise.resolve("ok" as const);
  }

  recordMismatch(input: { claimId: string; smsId: string; reason: string }) {
    const c = this.claims.get(input.claimId);
    const sms = this.sms.find((x) => x.id === input.smsId);
    const s = c === undefined ? undefined : this.sessions.get(c.sessionId);
    const ok = c !== undefined && sms !== undefined && s !== undefined &&
      s.activeClaimId === c.id && c.status === "pending" &&
      s.status === "pending" && sms.status === "unmatched" &&
      sms.merchantId === c.merchantId;
    if (!ok) return Promise.resolve("conflict" as const);
    c.status = "mismatch";
    c.reason = input.reason;
    c.candidateSmsId = sms.id;
    s.status = "mismatch";
    return Promise.resolve("ok" as const);
  }

  recordRejected(
    input: { claimId: string; userId: string; note: string | null },
  ) {
    const c = this.claims.get(input.claimId);
    const s = c === undefined ? undefined : this.sessions.get(c.sessionId);
    const ok = c !== undefined && s !== undefined && s.activeClaimId === c.id &&
      c.status === "mismatch" && s.status === "mismatch";
    if (!ok) return Promise.resolve("conflict" as const);
    c.status = "rejected";
    s.status = "rejected";
    return Promise.resolve("ok" as const);
  }

  findMismatchClaimBySms(smsId: string) {
    for (const c of this.claims.values()) {
      if (c.candidateSmsId === smsId && c.status === "mismatch") {
        return Promise.resolve({ ...c });
      }
    }
    return Promise.resolve(null);
  }

  getSmsResults(merchantId: string, smsIds: string[]) {
    const out: SmsResult[] = [];
    for (const id of smsIds) {
      const sms = this.sms.find((x) =>
        x.id === id && x.merchantId === merchantId
      );
      if (sms === undefined) continue;
      const match = this.matches.find((m) => m.smsId === sms.id) ?? null;
      let claim: PaymentClaim | undefined = match === null
        ? undefined
        : this.claims.get(match.claimId);
      if (claim === undefined) {
        // The newest claim that named this SMS as its candidate (mismatch, or rejected after it).
        for (const c of this.claims.values()) {
          if (c.candidateSmsId === sms.id) claim = c;
        }
      }
      const session = claim === undefined
        ? undefined
        : this.sessions.get(claim.sessionId);
      out.push({
        sms: { ...sms },
        claim: claim === undefined ? null : { ...claim },
        session: session === undefined ? null : { ...session },
        match: match === null ? null : { ...match },
      });
    }
    return Promise.resolve(out);
  }

  expireDue(nowIso: string) {
    const now = Date.parse(nowIso);
    let sessions = 0;
    let claims = 0;
    for (const s of this.sessions.values()) {
      if (s.status === "open" && now > Date.parse(s.submitDeadline)) {
        s.status = "expired";
        sessions++;
      } else if (s.status === "pending" && s.activeClaimId !== null) {
        const c = this.claims.get(s.activeClaimId);
        if (
          c !== undefined && c.status === "pending" &&
          now > Date.parse(c.matchDeadline)
        ) {
          c.status = "expired";
          s.status = "expired";
          claims++;
          sessions++;
        }
      }
    }
    return Promise.resolve({ sessions, claims });
  }

  hitRateLimit(key: string, limit: number, windowSeconds: number) {
    const window = Math.floor(this.now() / (windowSeconds * 1000));
    const k = `${key}|${windowSeconds}|${window}`;
    const n = (this.rateCounts.get(k) ?? 0) + 1;
    this.rateCounts.set(k, n);
    return Promise.resolve(n <= limit);
  }

  // ---- Spec 17 ----

  readonly connections = new Map<string, ConnectionRecord>();
  readonly orderSyncs = new Map<string, OrderSync>();

  /** Test-only: a Shopify (OAuth) connection like the spec 10 callback makes. */
  addShopifyConnection(merchantId: string, shopDomain: string): string {
    const id = crypto.randomUUID();
    this.connections.set(id, {
      id,
      merchantId,
      platform: "shopify",
      kind: "oauth",
      siteName: shopDomain,
      siteUrl: `https://${shopDomain}`,
      webhookUrl: null,
      apiKeyPrefix: null,
      status: "active",
      lastError: null,
      connectedAt: this.iso(),
      apiKeyHash: null,
      secretVersion: 1,
    });
    return id;
  }

  listConnections(merchantId: string) {
    return Promise.resolve(
      [...this.connections.values()]
        .filter((c) => c.merchantId === merchantId)
        .sort((a, b) => a.connectedAt.localeCompare(b.connectedAt))
        .map((c) => ({ ...c })),
    );
  }

  getConnection(id: string) {
    const c = this.connections.get(id);
    return Promise.resolve(c === undefined ? null : { ...c });
  }

  findConnectionByKeyHash(apiKeyHash: string) {
    for (const c of this.connections.values()) {
      if (c.apiKeyHash === apiKeyHash) return Promise.resolve({ ...c });
    }
    return Promise.resolve(null);
  }

  createApiConnection(f: NewApiConnection) {
    for (const c of this.connections.values()) {
      if (
        c.merchantId === f.merchantId && c.platform === f.platform &&
        c.siteUrl === f.siteUrl && c.status === "active"
      ) {
        return Promise.resolve("duplicate" as const);
      }
    }
    const c: ConnectionRecord = {
      id: crypto.randomUUID(),
      merchantId: f.merchantId,
      platform: f.platform,
      kind: "api",
      siteName: f.siteName,
      siteUrl: f.siteUrl,
      webhookUrl: null,
      apiKeyPrefix: f.apiKeyPrefix,
      status: "active",
      lastError: null,
      connectedAt: this.iso(),
      apiKeyHash: f.apiKeyHash,
      secretVersion: 1,
    };
    this.connections.set(c.id, c);
    return Promise.resolve({ ...c });
  }

  updateConnection(id: string, fields: ConnectionUpdate) {
    const c = this.connections.get(id);
    if (c === undefined) return Promise.reject(new StoreError("notFound"));
    Object.assign(c, fields);
    return Promise.resolve({ ...c });
  }

  findSessionByExternalOrder(storeId: string, externalOrderId: string) {
    for (const s of this.sessions.values()) {
      if (s.storeId === storeId && s.externalOrderId === externalOrderId) {
        return Promise.resolve({ ...s });
      }
    }
    return Promise.resolve(null);
  }

  enqueueOrderSync(merchantId: string, sessionId: string) {
    for (const o of this.orderSyncs.values()) {
      if (o.sessionId === sessionId) return Promise.resolve({ ...o });
    }
    const o: OrderSync = {
      id: crypto.randomUUID(),
      merchantId,
      sessionId,
      status: "pending",
      attempts: 0,
      nextAttemptAt: this.iso(),
      lastError: null,
    };
    this.orderSyncs.set(o.id, o);
    return Promise.resolve({ ...o });
  }

  listDueOrderSyncs(nowIso: string, limit: number) {
    const now = Date.parse(nowIso);
    return Promise.resolve(
      [...this.orderSyncs.values()]
        .filter((o) =>
          o.status === "pending" && Date.parse(o.nextAttemptAt) <= now
        )
        .sort((a, b) => a.nextAttemptAt.localeCompare(b.nextAttemptAt))
        .slice(0, limit)
        .map((o) => ({ ...o })),
    );
  }

  updateOrderSync(id: string, fields: OrderSyncUpdate) {
    const o = this.orderSyncs.get(id);
    if (o === undefined) return Promise.reject(new StoreError("notFound"));
    Object.assign(o, fields);
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
  const store = demoStore(now);
  const notifier = new NoopNotifier();
  return {
    store,
    users: new FakeUserVerifier(new Map([[DEMO.userToken, DEMO.userId]])),
    matcher: new StoreMatcher(store, notifier, consoleLogger),
    now,
    log: consoleLogger,
    limiter: storeLimiter(store),
    notifier,
  };
}

let local: Deps | null = null;

/** BDPAY_FAKE_STORE=1 -> one FakeStore per worker; otherwise null (index.ts answers 503 storeNotReady). */
export function depsFromEnv(
  get: (name: string) => string | undefined,
): Deps | null {
  if (get("BDPAY_FAKE_STORE") !== "1") return null;
  local ??= {
    ...demoDeps(),
    release: releaseFromEnv(get),
    config: {
      payPageOrigin: get("PAY_PAGE_ORIGIN"),
      cronSecret: get("CRON_SECRET"),
      rateLimitPepper: get("RATE_LIMIT_PEPPER"),
      payTokenSecret: get("PAY_TOKEN_SECRET"),
      payPageUrl: get("PAY_PAGE_URL"),
    },
  };
  return local;
}
