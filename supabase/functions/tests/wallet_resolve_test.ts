import assert from "node:assert/strict";
import type { Wallet } from "../_shared/types.ts";
import { resolveWallet } from "../_shared/wallet_resolve.ts";

const w = (id: string, over: Partial<Wallet> = {}): Wallet => ({
  id,
  merchantId: "m1",
  operator: "bkash",
  walletNumber: "01700000000",
  accountType: "merchant",
  simSlot: "sim1",
  isActive: true,
  ...over,
});

Deno.test("by simSlot: the wallet on the same SIM", () => {
  const wallets = [w("a", { simSlot: "sim1" }), w("b", { simSlot: "sim2" })];
  assert.equal(resolveWallet(wallets, "bkash", "sim2")?.id, "b");
});

Deno.test("by single wallet: the only active wallet of that operator", () => {
  const wallets = [w("a", { simSlot: "sim1" }), w("n", { operator: "nagad" })];
  assert.equal(resolveWallet(wallets, "bkash", "sim2")?.id, "a");
  assert.equal(resolveWallet(wallets, "bkash", "unknown")?.id, "a");
});

Deno.test("null: two wallets and none on the slot, unknown slot, or no wallet", () => {
  const two = [w("a", { simSlot: "sim1" }), w("b", { simSlot: "sim1" })];
  assert.equal(resolveWallet(two, "bkash", "sim2"), null);
  assert.equal(resolveWallet(two, "bkash", "unknown"), null);
  assert.equal(resolveWallet(two, "rocket", "sim1"), null);
  assert.equal(resolveWallet([], "bkash", "sim1"), null);
});

Deno.test("inactive wallets are ignored", () => {
  const wallets = [
    w("old", { simSlot: "sim2", isActive: false }),
    w("a", { simSlot: "sim1" }),
  ];
  assert.equal(resolveWallet(wallets, "bkash", "sim2")?.id, "a");
});
