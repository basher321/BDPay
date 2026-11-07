// Spec 08 record types. Wire names match the future SQL CHECK values (spec 12).
// Times are ISO 8601 UTC strings; money is whole poisha; phone and wallet numbers are digit strings.

export type Operator = "bkash" | "nagad" | "rocket" | "upay";
export type DeviceStatus = "active" | "revoked";
/** CLAUDE.md's list (plan D69). Spec 08 never writes "received". */
export type SmsStatus = "received" | "unmatched" | "matched" | "rejected";
export type RejectReason =
  | "senderNotTrusted"
  | "blocked"
  | "notIncoming"
  | "parseFailed"
  | "hashMismatch"
  | "tooOld";
export type VerifyStatus = "pending" | "verified" | "mismatch" | "rejected";
export type SimSlot = "sim1" | "sim2" | "unknown";
export type AccountType = "merchant" | "agent";
export type ActorType = "user" | "device" | "system";

export const OPERATORS: readonly Operator[] = [
  "bkash",
  "nagad",
  "rocket",
  "upay",
];
export const SIM_SLOTS: readonly SimSlot[] = ["sim1", "sim2", "unknown"];

export interface Device {
  id: string;
  merchantId: string;
  name: string;
  installId: string;
  /** base64 X.509 SubjectPublicKeyInfo of the phone's P-256 key. The private key never leaves the phone. */
  publicKeySpki: string;
  status: DeviceStatus;
  appVersion: string;
  androidVersion: string;
  lastSeenAt: string;
  createdAt: string;
}

export interface Wallet {
  id: string;
  merchantId: string;
  operator: Operator;
  walletNumber: string;
  accountType: AccountType;
  simSlot: SimSlot;
  isActive: boolean;
}

export interface SmsRecord {
  id: string;
  merchantId: string;
  deviceId: string;
  walletId: string | null;
  sender: string;
  /** null when blocked (never keep OTP text). */
  body: string | null;
  receivedAt: string;
  serverReceivedAt: string;
  simSlot: SimSlot;
  dedupeHash: string;
  operator: Operator | null;
  /** null on rejected rows (plan D71). */
  trxId: string | null;
  amountPoisha: number | null;
  payerNumber: string | null;
  status: SmsStatus;
  rejectReason: RejectReason | null;
  parserVersion: number;
}

export interface AuditEntry {
  /** null only for system-wide entries such as the expiry job (spec 12). */
  merchantId: string | null;
  actorType: ActorType;
  actorId: string;
  action: string;
  entity: string;
  entityId: string;
  /** Never keys, tokens, signatures or SMS fields. */
  data: Record<string, string | number | boolean | null>;
}

// ---- Spec 09: payment sessions, claims and matches ----

export type SessionStatus =
  | "open"
  | "pending"
  | "verified"
  | "mismatch"
  | "expired"
  | "rejected";
/** "superseded" = replaced by a newer claim on the same session (spec 09; plan 09 D31). */
export type ClaimStatus =
  | "pending"
  | "verified"
  | "mismatch"
  | "rejected"
  | "expired"
  | "superseded";
export type MatchMethod = "auto" | "manual";

export interface PaymentSession {
  id: string;
  merchantId: string;
  storeId: string;
  /** SHA-256 of the pay token; the token itself is never stored. */
  tokenHash: string;
  orderRef: string;
  externalOrderId: string | null;
  amountPoisha: number;
  status: SessionStatus;
  submitDeadline: string;
  attemptsLeft: number;
  returnUrl: string;
  activeClaimId: string | null;
  createdAt: string;
  verifiedAt: string | null;
}

export interface PaymentClaim {
  id: string;
  merchantId: string;
  sessionId: string;
  operator: Operator;
  /** Trimmed, upper case. */
  trxId: string;
  status: ClaimStatus;
  reason: string | null;
  candidateSmsId: string | null;
  matchDeadline: string;
  createdAt: string;
}

/** merchantId added for row-level security (plan 09 D35). */
export interface Match {
  id: string;
  merchantId: string;
  claimId: string;
  smsId: string;
  method: MatchMethod;
  userId: string | null;
  note: string | null;
  createdAt: string;
}

// ---- Spec 17: store connections (all website platforms) ----

/** Spec 17 fixed list (same values in Dart and the stores.platform CHECK). */
export const PLATFORMS = [
  "shopify",
  "wordpress",
  "webflow",
  "framer",
  "wix",
  "squarespace",
  "bubble",
  "drupal",
  "joomla",
  "hubspot",
  "duda",
  "react",
  "nextjs",
  "vue",
  "laravel",
  "nodejs",
  "django",
  "ghost",
  "magento",
  "prestashop",
  "webstudio",
  "astro",
  "sveltekit",
  "nuxt",
  "other",
] as const;
export type Platform = typeof PLATFORMS[number];
export type ConnectionKind = "oauth" | "api";
export type ConnectionStatus = "active" | "disabled" | "uninstalled";

/** What the app sees. Never holds the API key, its hash or any secret. */
export interface StoreConnection {
  id: string;
  merchantId: string;
  platform: Platform;
  kind: ConnectionKind;
  siteName: string;
  siteUrl: string | null;
  webhookUrl: string | null;
  apiKeyPrefix: string | null;
  status: ConnectionStatus;
  lastError: string | null;
  connectedAt: string;
}

/** Server-only fields next to the public ones. */
export interface ConnectionRecord extends StoreConnection {
  apiKeyHash: string | null;
  secretVersion: number;
}

export type OrderSyncStatus = "pending" | "done" | "failed";

export interface OrderSync {
  id: string;
  merchantId: string;
  sessionId: string;
  status: OrderSyncStatus;
  attempts: number;
  nextAttemptAt: string;
  lastError: string | null;
}
