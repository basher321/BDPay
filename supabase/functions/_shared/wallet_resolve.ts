// Spec 08 step e: which wallet an SMS was paid into. Pure.

import type { Operator, SimSlot, Wallet } from "./types.ts";

/**
 * An active wallet with the same operator and simSlot; else the only active wallet of that operator; else null.
 * simSlot "unknown" never matches by slot.
 */
export function resolveWallet(
  wallets: readonly Wallet[],
  operator: Operator,
  simSlot: SimSlot,
): Wallet | null {
  const same = wallets.filter((w) => w.isActive && w.operator === operator);
  if (simSlot !== "unknown") {
    const bySlot = same.find((w) => w.simSlot === simSlot);
    if (bySlot !== undefined) return bySlot;
  }
  return same.length === 1 ? same[0] : null;
}
