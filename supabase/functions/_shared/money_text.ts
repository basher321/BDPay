// Spec 10: Shopify money text -> whole poisha. Integer math on the digits only; no float ever.

const MONEY = /^([0-9]{1,13})(?:\.([0-9]{1,2}))?$/;

/**
 * "1250.00" -> 125000, "1250.5" -> 125050, "1250" -> 125000, "0.5" -> 50.
 * Returns null for anything else (negative, more than 2 decimals, exponents, commas, spaces, empty).
 */
export function moneyTextToPoisha(text: string): number | null {
  if (typeof text !== "string") return null;
  const m = MONEY.exec(text);
  if (!m) return null;
  const taka = Number.parseInt(m[1], 10);
  const fraction = m[2] === undefined
    ? 0
    : Number.parseInt(m[2].padEnd(2, "0"), 10);
  const poisha = taka * 100 + fraction;
  return Number.isSafeInteger(poisha) ? poisha : null;
}
