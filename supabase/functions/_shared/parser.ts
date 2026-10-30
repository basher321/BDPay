// Spec 08 server parser: a port of spec 06 (app/lib/domain/parser/parse_sms.dart and the Kotlin SmsFilter /
// ParserRules), with the same names. Pure; never logs; never throws on SMS text (an exception message could
// carry it). The rules come from Store.getParserRules, never from a file import here.

import { sha256Hex } from "./crypto.ts";
import { type Operator, OPERATORS } from "./types.ts";

export interface ParserRule {
  operator: Operator;
  senders: string[];
  incoming: RegExp;
  ignore: RegExp;
  trx: RegExp;
  amount: RegExp;
  payer: RegExp;
  balance: RegExp;
  reference: RegExp;
  payment: RegExp;
  version: number;
}

const PATTERN_KEYS = [
  "incoming",
  "ignore",
  "trx",
  "amount",
  "payer",
  "balance",
  "reference",
  "payment",
] as const;

/**
 * Compiles the rules file (a JSON array, one object per operator). Patterns have no inline flags and are
 * compiled case-insensitive, like Kotlin and Dart. Throws RangeError with a fixed message on a bad file.
 */
export function loadRules(json: unknown): ParserRule[] {
  if (!Array.isArray(json)) throw new RangeError("rules: not an array");
  return json.map((o): ParserRule => {
    if (typeof o !== "object" || o === null) {
      throw new RangeError("rules: not an object");
    }
    const r = o as Record<string, unknown>;
    if (!OPERATORS.includes(r.operator as Operator)) {
      throw new RangeError("rules: unknown operator");
    }
    if (
      !Array.isArray(r.senders) ||
      !r.senders.every((s) => typeof s === "string")
    ) {
      throw new RangeError("rules: senders");
    }
    if (!Number.isSafeInteger(r.version)) {
      throw new RangeError("rules: version");
    }
    const patterns = {} as Record<(typeof PATTERN_KEYS)[number], RegExp>;
    for (const key of PATTERN_KEYS) {
      if (typeof r[key] !== "string") throw new RangeError(`rules: ${key}`);
      try {
        patterns[key] = new RegExp(r[key] as string, "i");
      } catch {
        throw new RangeError(`rules: bad pattern ${key}`);
      }
    }
    return {
      operator: r.operator as Operator,
      senders: r.senders as string[],
      ...patterns,
      version: r.version as number,
    };
  });
}

/** The highest rule version in the file (plan D70). */
export function rulesVersion(rules: readonly ParserRule[]): number {
  return rules.reduce((v, r) => Math.max(v, r.version), 0);
}

/** Trimmed, lower case (Kotlin: trim().lowercase(Locale.ROOT)). */
export function normalizeSender(sender: string): string {
  return sender.trim().toLowerCase();
}

const BANGLA_ZERO = 0x09e6;

// The Unicode spaces Dart's \s knows and Java's \s does not; they become ' ' on all sides (same list).
const UNICODE_SPACES = new Set([
  0x00a0,
  0x1680,
  0x2000,
  0x2001,
  0x2002,
  0x2003,
  0x2004,
  0x2005,
  0x2006,
  0x2007,
  0x2008,
  0x2009,
  0x200a,
  0x2028,
  0x2029,
  0x202f,
  0x205f,
  0x3000,
  0xfeff,
]);

/** Bangla digits -> English digits, Unicode spaces -> ' '. Same as Kotlin normalizeBody / Dart normalizeSmsBody. */
export function normalizeSmsBody(body: string): string {
  let out = "";
  for (let i = 0; i < body.length; i++) {
    const c = body.charCodeAt(i);
    if (c >= BANGLA_ZERO && c <= BANGLA_ZERO + 9) {
      out += String.fromCharCode(c - BANGLA_ZERO + 0x30);
    } else if (UNICODE_SPACES.has(c)) out += " ";
    else out += body[i];
  }
  return out;
}

/** The rule whose senders contain sender, compared after trim, case-insensitive. */
export function ruleForSender(
  rules: readonly ParserRule[],
  sender: string,
): ParserRule | null {
  const s = normalizeSender(sender);
  return rules.find((r) => r.senders.some((x) => normalizeSender(x) === s)) ??
    null;
}

/** SHA-256 hex of the normalized sender + "|" + the body as received - the app's formula (plan D68). */
export function dedupeHash(sender: string, body: string): Promise<string> {
  return sha256Hex(`${normalizeSender(sender)}|${body}`);
}

export type FilterResult =
  | { result: "keep"; rule: ParserRule }
  | {
    result: "senderNotTrusted" | "blocked" | "notIncoming";
    rule: ParserRule | null;
  };

/** Spec 06 keep rule steps 2, 4 and 5 (monitoring and operator settings are phone-side only). */
export function filterSms(
  rules: readonly ParserRule[],
  sender: string,
  body: string,
): FilterResult {
  const rule = ruleForSender(rules, sender);
  if (rule === null) return { result: "senderNotTrusted", rule: null };
  const text = normalizeSmsBody(body);
  if (rule.ignore.test(text)) return { result: "blocked", rule };
  if (!rule.incoming.test(text)) return { result: "notIncoming", rule };
  return { result: "keep", rule };
}

const AMOUNT_TEXT = /^([0-9]{1,13})(?:\.([0-9]{1,2}))?$/;

/** "1,250.50" -> 125050, "1,250.5" -> 125050, "1,250" -> 125000, "0.5" -> 50. Whole-number math; null if not an amount. */
export function amountTextToPoisha(text: string): number | null {
  const m = AMOUNT_TEXT.exec(text.replaceAll(",", ""));
  if (m === null) return null;
  const taka = Number.parseInt(m[1], 10);
  const poisha = m[2] === undefined
    ? 0
    : Number.parseInt(m[2].padEnd(2, "0"), 10);
  return taka * 100 + poisha;
}

export type ParseError = "unknownSender" | "noTrxId" | "noAmount";

export interface ParsedSms {
  operator: Operator | null;
  /** Upper case. */
  trxId: string | null;
  amountPoisha: number | null;
  payerNumber: string | null;
  balancePoisha: number | null;
  reference: string | null;
  kind: "received" | "payment";
  errors: ParseError[];
  /** A TrxID and an amount were found. */
  ok: boolean;
}

function group1(re: RegExp, text: string): string | null {
  return re.exec(text)?.[1]?.trim() ?? null;
}

/** The first capture group that matched (the payer pattern has two forms). */
function firstGroup(re: RegExp, text: string): string | null {
  const m = re.exec(text);
  if (m === null) return null;
  for (let i = 1; i < m.length; i++) {
    if (m[i]) return m[i];
  }
  return null;
}

/** Pure parse of one SMS with the rules, as Dart parseSms. */
export function parseSms(
  sender: string,
  body: string,
  rules: readonly ParserRule[],
): ParsedSms {
  const rule = ruleForSender(rules, sender);
  if (rule === null) {
    return {
      operator: null,
      trxId: null,
      amountPoisha: null,
      payerNumber: null,
      balancePoisha: null,
      reference: null,
      kind: "received",
      errors: ["unknownSender"],
      ok: false,
    };
  }
  const text = normalizeSmsBody(body);
  const trx = group1(rule.trx, text)?.toUpperCase() ?? null;
  const amountText = group1(rule.amount, text);
  const amount = amountText === null ? null : amountTextToPoisha(amountText);
  const balanceText = group1(rule.balance, text);
  const errors: ParseError[] = [];
  if (trx === null || trx === "") errors.push("noTrxId");
  if (amount === null) errors.push("noAmount");
  return {
    operator: rule.operator,
    trxId: trx,
    amountPoisha: amount,
    payerNumber: firstGroup(rule.payer, text),
    balancePoisha: balanceText === null
      ? null
      : amountTextToPoisha(balanceText),
    reference: group1(rule.reference, text),
    kind: rule.payment.test(text) ? "payment" : "received",
    errors,
    ok: errors.length === 0,
  };
}
