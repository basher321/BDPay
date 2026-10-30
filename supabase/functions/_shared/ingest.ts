// Spec 08 sms-ingest: the phone sends the SMS it caught (signed device request). The server re-checks the hash,
// re-runs the filter and parser with its own rules, and stores each SMS once. The device's own parse is never
// read. One bad item never fails the batch.

import { checkDeviceRequest } from "./device_auth.ts";
import { type Deps, isObject, parseJson, readBody, replier } from "./http.ts";
import { dedupeHash, filterSms, loadRules, parseSms } from "./parser.ts";
import {
  type Device,
  type RejectReason,
  SIM_SLOTS,
  type SimSlot,
  type SmsRecord,
  type SmsStatus,
  type VerifyStatus,
  type Wallet,
} from "./types.ts";
import { resolveWallet } from "./wallet_resolve.ts";

export const FN = "sms-ingest";
export const MAX_ITEMS = 50;
export const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

export const REJECT_MESSAGES: Record<RejectReason, string> = {
  senderNotTrusted: "প্রেরক বিশ্বস্ত নয়",
  blocked: "OTP/অফার — রাখা হয়নি",
  notIncoming: "টাকা গ্রহণের এসএমএস নয়",
  parseFailed: "ফরম্যাট বোঝা যায়নি",
  hashMismatch: "ডেটা মেলেনি — আবার পাঠান",
  tooOld: "৭ দিনের বেশি পুরনো",
};

interface Item {
  localId: string;
  sender: string;
  body: string;
  receivedAt: number;
  simSlot: SimSlot;
  dedupeHash: string;
}

export interface ItemResult {
  localId: string;
  smsId: string | null;
  result: "accepted" | "duplicate" | "rejected";
  reason: RejectReason | null;
  verifyStatus: VerifyStatus;
  serverMessage: string | null;
}

const str = (v: unknown, max: number): v is string =>
  typeof v === "string" && v.length <= max;

/** Bad shape -> null (400 for the batch, as the spec says). */
function readItems(v: unknown): Item[] | null {
  if (!isObject(v) || !Array.isArray(v.items)) return null;
  if (v.items.length < 1 || v.items.length > MAX_ITEMS) return null;
  const items: Item[] = [];
  for (const it of v.items) {
    if (!isObject(it)) return null;
    const { localId, sender, body, receivedAt, simSlot } = it;
    if (!str(localId, 100) || localId === "") return null;
    if (!str(sender, 100) || !str(body, 10_000)) return null;
    if (typeof receivedAt !== "string") return null;
    const t = Date.parse(receivedAt);
    if (Number.isNaN(t)) return null;
    if (!SIM_SLOTS.includes(simSlot as SimSlot)) return null;
    if (typeof it.dedupeHash !== "string") return null;
    items.push({
      localId,
      sender,
      body,
      receivedAt: t,
      simSlot: simSlot as SimSlot,
      dedupeHash: it.dedupeHash.toLowerCase(),
    });
  }
  return items;
}

const VERIFY_OF: Record<SmsStatus, VerifyStatus> = {
  received: "pending",
  unmatched: "pending",
  matched: "verified",
  rejected: "rejected",
};

/** A stored row's current result (plan D72). */
function existingResult(localId: string, sms: SmsRecord): ItemResult {
  return {
    localId,
    smsId: sms.id,
    result: "duplicate",
    reason: sms.rejectReason,
    verifyStatus: VERIFY_OF[sms.status],
    serverMessage: sms.rejectReason === null
      ? null
      : REJECT_MESSAGES[sms.rejectReason],
  };
}

function rejected(
  localId: string,
  smsId: string | null,
  reason: RejectReason,
): ItemResult {
  return {
    localId,
    smsId,
    result: "rejected",
    reason,
    verifyStatus: "rejected",
    serverMessage: REJECT_MESSAGES[reason],
  };
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const reply = replier(FN, req, deps.log);
  if (req.method !== "POST") return reply.fail(405, "methodNotAllowed");
  const raw = await readBody(req);
  if (raw === null) return reply.fail(413, "tooLarge");
  const auth = await checkDeviceRequest(
    FN,
    req.headers,
    raw,
    deps.store,
    deps.now(),
  );
  if (!auth.ok) return reply.fail(auth.status, auth.code);
  const device = auth.device;
  const items = readItems(parseJson(raw));
  if (items === null) return reply.fail(400, "badRequest", device.merchantId);

  const rulesRow = await deps.store.getParserRules();
  const rules = loadRules(rulesRow.rules);
  const wallets = await deps.store.listActiveWallets(device.merchantId);
  const ctx = { deps, device, rules, version: rulesRow.version, wallets };

  const results: ItemResult[] = [];
  for (const item of items) results.push(await ingestOne(ctx, item));
  return reply.ok({ results }, device.merchantId);
}

interface Ctx {
  deps: Deps;
  device: Device;
  rules: ReturnType<typeof loadRules>;
  version: number;
  wallets: Wallet[];
}

async function ingestOne(ctx: Ctx, item: Item): Promise<ItemResult> {
  const { deps, device } = ctx;
  const merchantId = device.merchantId;

  // a. The hash must match what was sent (not stored otherwise).
  const hash = await dedupeHash(item.sender, item.body);
  if (hash !== item.dedupeHash) {
    return rejected(item.localId, null, "hashMismatch");
  }

  // b. Already stored -> its current result.
  const found = await deps.store.findSmsByDedupe(merchantId, hash);
  if (found !== null) return existingResult(item.localId, found);

  // d (clamp). A receivedAt in the future becomes the server time.
  const now = deps.now();
  const receivedAt = Math.min(item.receivedAt, now);
  const base: Omit<SmsRecord, "id"> = {
    merchantId,
    deviceId: device.id,
    walletId: null,
    sender: item.sender,
    body: item.body,
    receivedAt: new Date(receivedAt).toISOString(),
    serverReceivedAt: new Date(now).toISOString(),
    simSlot: item.simSlot,
    dedupeHash: hash,
    operator: null,
    trxId: null,
    amountPoisha: null,
    payerNumber: null,
    status: "rejected",
    rejectReason: null,
    parserVersion: ctx.version,
  };

  const storeRejected = async (
    reason: RejectReason,
    extra: Partial<SmsRecord> = {},
  ) => {
    const { sms, created } = await deps.store.insertSms({
      ...base,
      ...extra,
      rejectReason: reason,
    });
    return created
      ? rejected(item.localId, sms.id, reason)
      : existingResult(item.localId, sms);
  };

  // c. Filter and parse with the server rules.
  const filter = filterSms(ctx.rules, item.sender, item.body);
  const operator = filter.rule?.operator ?? null;
  if (filter.result === "senderNotTrusted") {
    return storeRejected("senderNotTrusted");
  }
  if (filter.result === "blocked") {
    return storeRejected("blocked", { operator, body: null });
  }
  if (filter.result === "notIncoming") {
    return storeRejected("notIncoming", { operator });
  }
  const parsed = parseSms(item.sender, item.body, ctx.rules);
  if (!parsed.ok) return storeRejected("parseFailed", { operator });

  // d. Older than 7 days.
  if (now - receivedAt > MAX_AGE_MS) {
    return storeRejected("tooOld", { operator });
  }

  // e. Wallet; f. store as unmatched, then the matcher.
  const wallet = resolveWallet(ctx.wallets, parsed.operator!, item.simSlot);
  const { sms, created } = await deps.store.insertSms({
    ...base,
    walletId: wallet?.id ?? null,
    operator: parsed.operator,
    trxId: parsed.trxId!.trim().toUpperCase(),
    amountPoisha: parsed.amountPoisha,
    payerNumber: parsed.payerNumber,
    status: "unmatched",
  });
  if (!created) return existingResult(item.localId, sms);
  const outcome = await deps.matcher.onSmsStored(sms);
  return {
    localId: item.localId,
    smsId: sms.id,
    result: "accepted",
    reason: null,
    verifyStatus: outcome.verifyStatus,
    serverMessage: outcome.serverMessage,
  };
}
