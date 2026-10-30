// Spec 12a contract suite: what a store needs to offer the shared tests. Each test makes its own merchant with
// random ids and uses only that merchant's rows, so the same tests can run on FakeStore and (later) on PgStore
// against a database where nothing is ever deleted.

import { FakeStore } from "../../_shared/fake_store.ts";
import type { Store } from "../../_shared/store.ts";
import type {
  AuditEntry,
  Operator,
  SimSlot,
  Wallet,
} from "../../_shared/types.ts";

export interface TestMerchant {
  merchantId: string;
  userId: string;
  email: string;
  businessName: string;
}

export interface WalletFields {
  operator?: Operator;
  simSlot?: SimSlot;
  isActive?: boolean;
}

/** Test-only helpers that a Store does not offer (merchants and wallets are made by the app, not the functions). */
export interface StoreMaker {
  name: string;
  store: Store;
  newMerchant(): Promise<TestMerchant>;
  addWallet(merchantId: string, fields?: WalletFields): Promise<Wallet>;
  /** The merchant's audit rows, oldest first. */
  readAudit(merchantId: string): Promise<AuditEntry[]>;
  /** Spec 09: a store (Shopify shop) row for payment sessions; returns its id. */
  newStoreId(merchantId: string): Promise<string>;
}

/** A random valid wallet number: 01 + [3-9] + 8 digits. */
export function randomWalletNumber(): string {
  const digits = crypto.getRandomValues(new Uint8Array(9));
  return "01" + String(3 + (digits[0] % 7)) +
    Array.from(digits.subarray(1), (d) => String(d % 10)).join("");
}

export function randomHex(bytes = 32): string {
  return Array.from(
    crypto.getRandomValues(new Uint8Array(bytes)),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}

/** FakeStore maker: one FakeStore per maker, like one database shared by many tests. */
export function fakeMaker(): StoreMaker {
  const store = new FakeStore();
  return {
    name: "FakeStore",
    store,
    newMerchant() {
      const m = {
        merchantId: crypto.randomUUID(),
        userId: crypto.randomUUID(),
        email: `t-${crypto.randomUUID()}@bdpay.test`,
        businessName: "Contract shop",
      };
      store.addOwner(m.userId, m.merchantId);
      store.setMerchantName(m.merchantId, m.businessName);
      return Promise.resolve(m);
    },
    addWallet(merchantId, fields = {}) {
      const wallet: Wallet = {
        id: crypto.randomUUID(),
        merchantId,
        operator: fields.operator ?? "bkash",
        walletNumber: randomWalletNumber(),
        accountType: "merchant",
        simSlot: fields.simSlot ?? "sim1",
        isActive: fields.isActive ?? true,
      };
      store.addWallet(wallet);
      return Promise.resolve(wallet);
    },
    readAudit(merchantId) {
      return Promise.resolve(
        store.audit.filter((a) => a.merchantId === merchantId),
      );
    },
    newStoreId() {
      return Promise.resolve(crypto.randomUUID());
    },
  };
}
