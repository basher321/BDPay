// Spec 12a: the Store on the real Postgres database (service role, query builder and rpc only - no raw SQL).
// Every record has the same shape FakeStore returns (camelCase, ISO UTC times, whole poisha). Unexpected database
// errors become StoreError("db") with no row contents (never logged or returned as text).

import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.118.0";
import {
  type ClaimConflict,
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

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

const iso = (v: unknown): string => new Date(String(v)).toISOString();
const isoOrNull = (
  v: unknown,
): string | null => (v === null || v === undefined ? null : iso(v));

export const toDevice = (r: Row): Device => ({
  id: r.id,
  merchantId: r.merchant_id,
  name: r.name,
  installId: r.install_id,
  publicKeySpki: r.public_key_spki,
  status: r.status,
  appVersion: r.app_version,
  androidVersion: r.android_version,
  lastSeenAt: iso(r.last_seen_at),
  createdAt: iso(r.created_at),
});

export const toWallet = (r: Row): Wallet => ({
  id: r.id,
  merchantId: r.merchant_id,
  operator: r.operator,
  walletNumber: r.wallet_number,
  accountType: r.account_type,
  simSlot: r.sim_slot,
  isActive: r.is_active,
});

export const toSms = (r: Row): SmsRecord => ({
  id: r.id,
  merchantId: r.merchant_id,
  deviceId: r.device_id,
  walletId: r.wallet_id,
  sender: r.sender,
  body: r.body,
  receivedAt: iso(r.received_at),
  serverReceivedAt: iso(r.server_received_at),
  simSlot: r.sim_slot,
  dedupeHash: r.dedupe_hash,
  operator: r.operator,
  trxId: r.trx_id,
  amountPoisha: r.amount_poisha === null ? null : Number(r.amount_poisha),
  payerNumber: r.payer_number,
  status: r.status,
  rejectReason: r.reject_reason,
  parserVersion: r.parser_version,
});

export const toSession = (r: Row): PaymentSession => ({
  id: r.id,
  merchantId: r.merchant_id,
  storeId: r.store_id,
  tokenHash: r.token_hash,
  orderRef: r.order_ref,
  externalOrderId: r.external_order_id,
  amountPoisha: Number(r.amount_poisha),
  status: r.status,
  submitDeadline: iso(r.submit_deadline),
  attemptsLeft: r.attempts_left,
  returnUrl: r.return_url,
  activeClaimId: r.active_claim_id,
  createdAt: iso(r.created_at),
  verifiedAt: isoOrNull(r.verified_at),
});

/** Spec 17: a stores row; Shopify rows (spec 10) have a shop_domain and no API key. */
export const toConnection = (r: Row): ConnectionRecord => ({
  id: r.id,
  merchantId: r.merchant_id,
  platform: r.platform,
  kind: r.platform === "shopify" ? "oauth" : "api",
  siteName: r.site_name ?? r.shop_domain ?? "",
  siteUrl: r.site_url ?? (r.shop_domain ? `https://${r.shop_domain}` : null),
  webhookUrl: r.webhook_url ?? null,
  apiKeyPrefix: r.api_key_prefix ?? null,
  status: r.status,
  lastError: r.last_error ?? null,
  connectedAt: iso(r.connected_at),
  apiKeyHash: r.api_key_hash ?? null,
  secretVersion: r.secret_version ?? 1,
});

const CONNECTION_COLUMNS =
  "id, merchant_id, platform, shop_domain, status, last_error, connected_at, site_name, site_url, " +
  "webhook_url, api_key_prefix, api_key_hash, secret_version";

export const toOrderSync = (r: Row): OrderSync => ({
  id: r.id,
  merchantId: r.merchant_id,
  sessionId: r.session_id,
  status: r.status,
  attempts: r.attempts,
  nextAttemptAt: iso(r.next_attempt_at),
  lastError: r.last_error ?? null,
});

export const toClaim = (r: Row): PaymentClaim => ({
  id: r.id,
  merchantId: r.merchant_id,
  sessionId: r.session_id,
  operator: r.operator,
  trxId: r.trx_id,
  status: r.status,
  reason: r.reason,
  candidateSmsId: r.candidate_sms_id,
  matchDeadline: iso(r.match_deadline),
  createdAt: iso(r.created_at),
});

export const toMatch = (r: Row): Match => ({
  id: r.id,
  merchantId: r.merchant_id,
  claimId: r.claim_id,
  smsId: r.sms_id,
  method: r.method,
  userId: r.user_id,
  note: r.note,
  createdAt: iso(r.created_at),
});

const deviceRow = (f: Partial<NewDevice> & DeviceUpdate): Row => {
  const out: Row = {};
  if (f.merchantId !== undefined) out.merchant_id = f.merchantId;
  if (f.name !== undefined) out.name = f.name;
  if (f.installId !== undefined) out.install_id = f.installId;
  if (f.publicKeySpki !== undefined) out.public_key_spki = f.publicKeySpki;
  if (f.status !== undefined) out.status = f.status;
  if (f.appVersion !== undefined) out.app_version = f.appVersion;
  if (f.androidVersion !== undefined) out.android_version = f.androidVersion;
  if (f.lastSeenAt !== undefined) out.last_seen_at = f.lastSeenAt;
  return out;
};

const LIVE = ["pending", "verified", "mismatch"];

export class PgStore implements Store {
  /** [debug] is for local / CI test runs only (never set in production): it gets the database error code. */
  constructor(
    private readonly db: SupabaseClient,
    private readonly debug?: (msg: string) => void,
  ) {}

  static fromEnv(
    url: string,
    serviceRoleKey: string,
    debug?: (msg: string) => void,
  ): PgStore {
    return new PgStore(
      createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: { "X-Client-Info": "bdpay-edge" } },
      }),
      debug,
    );
  }

  /** Unwraps a supabase-js result; any error -> StoreError("db") without details. */
  private ok<T>(res: { data: T | null; error: unknown }): T | null {
    if (res.error) {
      if (this.debug) {
        const e = res.error as { code?: string; message?: string };
        this.debug(`db error ${e.code ?? "?"}: ${e.message ?? ""}`);
      }
      throw new StoreError("db");
    }
    return res.data;
  }

  /** A single-row insert result; a missing row is a database error. */
  private must(r: unknown): Row {
    if (r === null || r === undefined) throw new StoreError("db");
    return r as Row;
  }

  private async rpc<T>(fn: string, args: Row): Promise<T> {
    return this.ok(await this.db.rpc(fn, args)) as T;
  }

  // ---- spec 08 ----

  async findMerchantForUser(userId: string) {
    const r = this.ok(
      await this.db.from("merchants").select("id").eq("owner_id", userId)
        .maybeSingle(),
    );
    return r === null ? null : { merchantId: (r as Row).id as string };
  }

  async countActiveDevices(merchantId: string) {
    const res = await this.db.from("devices").select("id", {
      count: "exact",
      head: true,
    })
      .eq("merchant_id", merchantId).eq("status", "active");
    if (res.error) throw new StoreError("db");
    return res.count ?? 0;
  }

  async findDeviceByInstall(merchantId: string, installId: string) {
    const r = this.ok(
      await this.db.from("devices").select("*").eq("merchant_id", merchantId)
        .eq("install_id", installId)
        .maybeSingle(),
    );
    return r === null ? null : toDevice(r as Row);
  }

  async createDevice(fields: NewDevice) {
    const r = this.ok(
      await this.db.from("devices").insert(deviceRow(fields)).select("*")
        .single(),
    );
    return toDevice(this.must(r));
  }

  async updateDevice(deviceId: string, fields: DeviceUpdate) {
    const r = this.ok(
      await this.db.from("devices").update(deviceRow(fields)).eq("id", deviceId)
        .select("*").maybeSingle(),
    );
    if (r === null) throw new StoreError("notFound");
    return toDevice(r as Row);
  }

  async getDevice(deviceId: string) {
    const r = this.ok(
      await this.db.from("devices").select("*").eq("id", deviceId)
        .maybeSingle(),
    );
    return r === null ? null : toDevice(r as Row);
  }

  async getParserRules(): Promise<ParserRulesRow> {
    const r = this.ok(
      await this.db.from("parser_rules").select("version, rules").eq(
        "is_active",
        true,
      ).maybeSingle(),
    );
    if (r === null) throw new StoreError("notFound");
    return { version: (r as Row).version, rules: (r as Row).rules };
  }

  async listActiveWallets(merchantId: string) {
    const r = this.ok(
      await this.db.from("wallets").select("*").eq("merchant_id", merchantId)
        .eq("is_active", true)
        .order("created_at"),
    );
    return ((r ?? []) as Row[]).map(toWallet);
  }

  async findSmsByDedupe(merchantId: string, dedupeHash: string) {
    const r = this.ok(
      await this.db.from("sms_messages").select("*").eq(
        "merchant_id",
        merchantId,
      ).eq("dedupe_hash", dedupeHash)
        .maybeSingle(),
    );
    return r === null ? null : toSms(r as Row);
  }

  async insertSms(record: Omit<SmsRecord, "id">) {
    const out = await this.rpc<Row>("insert_sms", {
      p: {
        merchant_id: record.merchantId,
        device_id: record.deviceId,
        wallet_id: record.walletId,
        sender: record.sender,
        body: record.body,
        received_at: record.receivedAt,
        server_received_at: record.serverReceivedAt,
        sim_slot: record.simSlot,
        dedupe_hash: record.dedupeHash,
        operator: record.operator,
        trx_id: record.trxId,
        amount_poisha: record.amountPoisha,
        payer_number: record.payerNumber,
        status: record.status,
        reject_reason: record.rejectReason,
        parser_version: record.parserVersion,
      },
    });
    return { sms: toSms(out.sms), created: out.created === true };
  }

  async writeAudit(entry: AuditEntry) {
    this.ok(
      await this.db.from("audit_log").insert({
        merchant_id: entry.merchantId,
        actor_type: entry.actorType,
        actor_id: entry.actorId,
        action: entry.action,
        entity: entry.entity,
        entity_id: entry.entityId,
        data: entry.data,
      }),
    );
  }

  // ---- spec 09 ----

  async createPaymentSession(f: NewPaymentSession) {
    const r = this.ok(
      await this.db.from("payment_sessions").insert({
        merchant_id: f.merchantId,
        store_id: f.storeId,
        token_hash: f.tokenHash,
        order_ref: f.orderRef,
        external_order_id: f.externalOrderId,
        amount_poisha: f.amountPoisha,
        return_url: f.returnUrl,
        submit_deadline: f.submitDeadline,
      }).select("*").single(),
    );
    return toSession(this.must(r));
  }

  private async one<T>(
    table: string,
    column: string,
    value: string,
    map: (r: Row) => T,
  ): Promise<T | null> {
    const r = this.ok(
      await this.db.from(table).select("*").eq(column, value).maybeSingle(),
    );
    return r === null ? null : map(r as Row);
  }

  getSessionByTokenHash(tokenHash: string) {
    return this.one("payment_sessions", "token_hash", tokenHash, toSession);
  }
  getSession(id: string) {
    return this.one("payment_sessions", "id", id, toSession);
  }
  getClaim(id: string) {
    return this.one("payment_claims", "id", id, toClaim);
  }
  getSms(id: string) {
    return this.one("sms_messages", "id", id, toSms);
  }

  async getMerchantName(merchantId: string) {
    const r = this.ok(
      await this.db.from("merchants").select("business_name").eq(
        "id",
        merchantId,
      ).maybeSingle(),
    );
    return r === null ? "" : String((r as Row).business_name);
  }

  async hasDeviceSeenSince(merchantId: string, sinceIso: string) {
    const res = await this.db.from("devices").select("id", {
      count: "exact",
      head: true,
    })
      .eq("merchant_id", merchantId).eq("status", "active").gte(
        "last_seen_at",
        sinceIso,
      );
    if (res.error) throw new StoreError("db");
    return (res.count ?? 0) > 0;
  }

  private async claimBy(
    merchantId: string,
    operator: Operator,
    trxId: string,
    statuses: string[],
  ) {
    const r = this.ok(
      await this.db.from("payment_claims").select("*").eq(
        "merchant_id",
        merchantId,
      ).eq("operator", operator)
        .eq("trx_id", trxId).in("status", statuses).order("created_at", {
          ascending: false,
        }).limit(1),
    );
    const rows = (r ?? []) as Row[];
    return rows.length === 0 ? null : toClaim(rows[0]);
  }

  findLiveClaimByTrx(merchantId: string, operator: Operator, trxId: string) {
    return this.claimBy(merchantId, operator, trxId, LIVE);
  }

  findPendingClaimByTrx(merchantId: string, operator: Operator, trxId: string) {
    return this.claimBy(merchantId, operator, trxId, ["pending"]);
  }

  async spendAttempt(sessionId: string) {
    const n = await this.rpc<number | null>("spend_attempt", {
      p_session_id: sessionId,
    });
    if (n === null) throw new StoreError("notFound");
    return n;
  }

  async submitClaim(
    input: { sessionId: string; operator: Operator; trxId: string },
  ) {
    const out = await this.rpc<Row>("submit_claim", {
      p_session_id: input.sessionId,
      p_operator: input.operator,
      p_trx_id: input.trxId,
    });
    if (out.claim) return { claim: toClaim(out.claim) };
    return { conflict: out.conflict as ClaimConflict };
  }

  async findUnmatchedSms(
    merchantId: string,
    operator: Operator,
    trxId: string,
  ) {
    const r = this.ok(
      await this.db.from("sms_messages").select("*").eq(
        "merchant_id",
        merchantId,
      ).eq("operator", operator)
        .eq("trx_id", trxId).eq("status", "unmatched").order("received_at")
        .limit(1),
    );
    const rows = (r ?? []) as Row[];
    return rows.length === 0 ? null : toSms(rows[0]);
  }

  async recordVerified(input: {
    claimId: string;
    smsId: string;
    method: MatchMethod;
    userId: string | null;
    note: string | null;
  }) {
    const r = await this.rpc<string>("record_verified", {
      p_claim_id: input.claimId,
      p_sms_id: input.smsId,
      p_method: input.method,
      p_user_id: input.userId,
      p_note: input.note,
    });
    return r === "ok" ? "ok" as const : "conflict" as const;
  }

  async recordMismatch(
    input: { claimId: string; smsId: string; reason: string },
  ) {
    const r = await this.rpc<string>("record_mismatch", {
      p_claim_id: input.claimId,
      p_sms_id: input.smsId,
      p_reason: input.reason,
    });
    return r === "ok" ? "ok" as const : "conflict" as const;
  }

  async recordRejected(
    input: { claimId: string; userId: string; note: string | null },
  ) {
    const r = await this.rpc<string>("record_rejected", {
      p_claim_id: input.claimId,
      p_user_id: input.userId,
      p_note: input.note,
    });
    return r === "ok" ? "ok" as const : "conflict" as const;
  }

  async findMismatchClaimBySms(smsId: string) {
    const r = this.ok(
      await this.db.from("payment_claims").select("*").eq(
        "candidate_sms_id",
        smsId,
      ).eq("status", "mismatch")
        .limit(1),
    );
    const rows = (r ?? []) as Row[];
    return rows.length === 0 ? null : toClaim(rows[0]);
  }

  async getSmsResults(
    merchantId: string,
    smsIds: string[],
  ): Promise<SmsResult[]> {
    const uuid =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    const ids = smsIds.filter((x) => uuid.test(x));
    if (ids.length === 0) return [];
    const rows = await this.rpc<Row[]>("get_sms_results", {
      p_merchant_id: merchantId,
      p_sms_ids: ids,
    });
    return (rows ?? []).map((r) => ({
      sms: toSms(r.sms),
      claim: r.claim ? toClaim(r.claim) : null,
      session: r.session ? toSession(r.session) : null,
      match: r.match ? toMatch(r.match) : null,
    }));
  }

  async expireDue(nowIso: string) {
    const r = await this.rpc<Row>("expire_due", { p_now: nowIso });
    return { sessions: Number(r.sessions), claims: Number(r.claims) };
  }

  async hitRateLimit(key: string, limit: number, windowSeconds: number) {
    return (await this.rpc<boolean>("hit_rate_limit", {
      p_key: key,
      p_limit: limit,
      p_window_seconds: windowSeconds,
    })) === true;
  }

  // ---- spec 17 ----

  async listConnections(merchantId: string) {
    const r = this.ok(
      await this.db.from("stores").select(CONNECTION_COLUMNS)
        .eq("merchant_id", merchantId).order("connected_at", {
          ascending: true,
        }),
    ) as Row[] | null;
    return (r ?? []).map(toConnection);
  }

  async getConnection(id: string) {
    if (!UUID.test(id)) return null;
    const r = this.ok(
      await this.db.from("stores").select(CONNECTION_COLUMNS).eq("id", id)
        .maybeSingle(),
    ) as Row | null;
    return r === null ? null : toConnection(r);
  }

  async findConnectionByKeyHash(apiKeyHash: string) {
    const r = this.ok(
      await this.db.from("stores").select(CONNECTION_COLUMNS)
        .eq("api_key_hash", apiKeyHash).maybeSingle(),
    ) as Row | null;
    return r === null ? null : toConnection(r);
  }

  async createApiConnection(f: NewApiConnection) {
    const res = await this.db.from("stores").insert({
      merchant_id: f.merchantId,
      platform: f.platform,
      site_name: f.siteName,
      site_url: f.siteUrl,
      api_key_prefix: f.apiKeyPrefix,
      api_key_hash: f.apiKeyHash,
    }).select(CONNECTION_COLUMNS).single();
    if ((res.error as { code?: string } | null)?.code === "23505") {
      return "duplicate" as const;
    }
    return toConnection(this.must(this.ok(res)));
  }

  async updateConnection(id: string, f: ConnectionUpdate) {
    const patch: Row = {};
    if (f.webhookUrl !== undefined) patch.webhook_url = f.webhookUrl;
    if (f.apiKeyPrefix !== undefined) patch.api_key_prefix = f.apiKeyPrefix;
    if (f.apiKeyHash !== undefined) patch.api_key_hash = f.apiKeyHash;
    if (f.status !== undefined) patch.status = f.status;
    if (!UUID.test(id)) throw new StoreError("notFound");
    const r = this.ok(
      await this.db.from("stores").update(patch).eq("id", id)
        .select(CONNECTION_COLUMNS).maybeSingle(),
    ) as Row | null;
    if (r === null) throw new StoreError("notFound");
    return toConnection(r);
  }

  async findSessionByExternalOrder(storeId: string, externalOrderId: string) {
    if (!UUID.test(storeId)) return null;
    const r = this.ok(
      await this.db.from("payment_sessions").select("*")
        .eq("store_id", storeId).eq("external_order_id", externalOrderId)
        .maybeSingle(),
    ) as Row | null;
    return r === null ? null : toSession(r);
  }

  async enqueueOrderSync(merchantId: string, sessionId: string) {
    this.ok(
      await this.db.from("order_syncs").upsert({
        merchant_id: merchantId,
        session_id: sessionId,
      }, { onConflict: "session_id", ignoreDuplicates: true }),
    );
    const r = this.ok(
      await this.db.from("order_syncs").select("*").eq("session_id", sessionId)
        .single(),
    );
    return toOrderSync(this.must(r));
  }

  async listDueOrderSyncs(nowIso: string, limit: number) {
    const r = this.ok(
      await this.db.from("order_syncs").select("*").eq("status", "pending")
        .lte("next_attempt_at", nowIso).order("next_attempt_at", {
          ascending: true,
        }).limit(limit),
    ) as Row[] | null;
    return (r ?? []).map(toOrderSync);
  }

  async updateOrderSync(id: string, f: OrderSyncUpdate) {
    this.ok(
      await this.db.from("order_syncs").update({
        status: f.status,
        attempts: f.attempts,
        next_attempt_at: f.nextAttemptAt,
        last_error: f.lastError,
      }).eq("id", id),
    );
  }
}
