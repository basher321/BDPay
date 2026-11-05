// Spec 13a local test helper: creates a payment session for a merchant email, amount and order ref, and prints
// the pay page URL (PAY_PAGE_URL + "?t=" + token, spec 10). Local only: refuses unless SUPABASE_URL is this machine
// (checked before anything else). Prints only the pay URL - never a key, token secret or other env value.
//
// Needs spec 09's createPaymentSession and spec 12a's Postgres store (plan 13a D170). Until they exist it stops
// with "not available" after the checks below.
//
// Run from the project root (you pass your own env file):
//   deno run --allow-net=127.0.0.1:54321 --allow-env --env-file=<your local env file> \
//     supabase/scripts/make_session.ts --email you@example.com --amount 1500.00 --order "#T1"

import { assertLocal } from "../functions/tests/integration/local_guard.ts";

/** What the script needs from the server side (spec 09 + 12a provide it). */
export interface SessionBackend {
  findMerchantIdByEmail(email: string): Promise<string | null>;
  createSession(
    fields: { merchantId: string; amountPoisha: number; orderRef: string },
  ): Promise<{ token: string }>;
}

export interface SessionArgs {
  email: string;
  amountPoisha: number;
  orderRef: string;
}

/** "1500", "1500.5", "1500.00" -> whole poisha. Commas, signs, 3 decimals or 0 are refused. No float math. */
export function parseAmountPoisha(text: string): number | null {
  const m = /^(\d{1,9})(?:\.(\d{1,2}))?$/.exec(text.trim());
  if (m === null) return null;
  const poisha = Number(m[1]) * 100 + Number((m[2] ?? "").padEnd(2, "0"));
  return poisha > 0 ? poisha : null;
}

export function parseArgs(args: string[]): SessionArgs {
  const get = (name: string) => {
    const i = args.indexOf(`--${name}`);
    return i >= 0 ? args[i + 1] : undefined;
  };
  const email = get("email")?.trim().toLowerCase();
  const amount = get("amount");
  const orderRef = get("order")?.trim();
  if (!email || !email.includes("@")) {
    throw new Error("usage: --email is missing");
  }
  if (amount === undefined) throw new Error("usage: --amount is missing");
  const amountPoisha = parseAmountPoisha(amount);
  if (amountPoisha === null) {
    throw new Error("usage: --amount must look like 1500.00");
  }
  if (!orderRef || orderRef.length > 64) {
    throw new Error("usage: --order is missing");
  }
  return { email, amountPoisha, orderRef };
}

/** The pay URL, plus the form the Android emulator reaches (its host is 10.0.2.2). */
export function payLinks(pageUrl: string, token: string): string[] {
  const link = `${pageUrl}?t=${encodeURIComponent(token)}`;
  const host = new URL(pageUrl).hostname;
  const emulator = host === "localhost" || host === "127.0.0.1"
    ? link.replace(host, "10.0.2.2")
    : null;
  return emulator === null ? [link] : [link, emulator];
}

const notBuilt = (): SessionBackend => {
  throw new Error(
    "not available: needs spec 09 (createPaymentSession) and spec 12a (Postgres store)",
  );
};

/** Returns the lines to print. Throws with a short message (never an env value). */
export async function main(
  env: (key: string) => string | undefined,
  args: string[],
  backend: (supabaseUrl: URL) => SessionBackend = notBuilt,
): Promise<string[]> {
  const url = assertLocal(env("SUPABASE_URL")); // before any client or network call
  const pageUrl = env("PAY_PAGE_URL");
  if (!pageUrl) throw new Error("refusing: PAY_PAGE_URL is not set");
  assertLocal(pageUrl);
  const a = parseArgs(args);
  const store = backend(url);
  const merchantId = await store.findMerchantIdByEmail(a.email);
  if (merchantId === null) throw new Error("no merchant for that email");
  const { token } = await store.createSession({
    merchantId,
    amountPoisha: a.amountPoisha,
    orderRef: a.orderRef,
  });
  return payLinks(pageUrl, token);
}

if (import.meta.main) {
  try {
    for (const line of await main((k) => Deno.env.get(k), Deno.args)) {
      console.log(line);
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : "";
    // Only this script's own short messages; anything else could carry details.
    const known = /^(refusing|usage|not available|no merchant)/.test(msg);
    console.error(known ? msg : "failed");
    Deno.exit(1);
  }
}
