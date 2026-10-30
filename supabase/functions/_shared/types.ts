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
  merchantId: string;
  actorType: ActorType;
  actorId: string;
  action: string;
  entity: string;
  entityId: string;
  /** Never keys, tokens, signatures or SMS fields. */
  data: Record<string, string | number | boolean | null>;
}
