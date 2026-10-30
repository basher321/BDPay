// Spec 08 Store interface. Edge Function logic talks only to this (CLAUDE.md Backend rules); spec 12 builds the
// tables and the real Postgres Store from this list. Every merchant-owned record carries merchantId.

import type { AuditEntry, Device, SmsRecord, Wallet } from "./types.ts";

/** An unexpected store failure. The code is short and fixed; it never carries row contents (spec 12a). */
export type StoreErrorCode = "notFound" | "conflict" | "db";

export class StoreError extends Error {
  constructor(readonly code: StoreErrorCode) {
    super(`store: ${code}`);
    this.name = "StoreError";
  }
}

export interface ParserRulesRow {
  version: number;
  /** The rules file's JSON array, as stored. parser.loadRules compiles it. */
  rules: unknown;
}

export type NewDevice = Omit<Device, "id" | "createdAt">;
export type DeviceUpdate = Partial<
  Pick<
    Device,
    | "name"
    | "publicKeySpki"
    | "status"
    | "appVersion"
    | "androidVersion"
    | "lastSeenAt"
  >
>;

export interface Store {
  /** The merchant the user owns, or null. */
  findMerchantForUser(userId: string): Promise<{ merchantId: string } | null>;
  countActiveDevices(merchantId: string): Promise<number>;
  findDeviceByInstall(
    merchantId: string,
    installId: string,
  ): Promise<Device | null>;
  createDevice(fields: NewDevice): Promise<Device>;
  updateDevice(deviceId: string, fields: DeviceUpdate): Promise<Device>;
  getDevice(deviceId: string): Promise<Device | null>;
  getParserRules(): Promise<ParserRulesRow>;
  listActiveWallets(merchantId: string): Promise<Wallet[]>;
  findSmsByDedupe(
    merchantId: string,
    dedupeHash: string,
  ): Promise<SmsRecord | null>;
  /**
   * If the same merchantId + dedupeHash exists, returns the existing row with created false.
   * Must be safe when two requests race.
   */
  insertSms(
    record: Omit<SmsRecord, "id">,
  ): Promise<{ sms: SmsRecord; created: boolean }>;
  writeAudit(entry: AuditEntry): Promise<void>;
}
