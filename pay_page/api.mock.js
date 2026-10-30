// MOCK - replaced by the real API in spec 13.
// An in-memory pretend server for the pay page. State lives only while the page is open.
import { isValidTrxId, normalizeTrxId } from "./logic.js";

const MINUTE = 60 * 1000;
const START_ATTEMPTS = 5;

const ALL_OPERATORS = [
  { operator: "bkash", walletNumber: "01700000001", accountType: "merchant" },
  { operator: "nagad", walletNumber: "01700000002", accountType: "merchant" },
  { operator: "rocket", walletNumber: "017000000031", accountType: "agent" },
  { operator: "upay", walletNumber: "01700000004", accountType: "merchant" },
];

// Demo tokens. "demo-one" (bKash only) is decision D24.
const TOKENS = {
  "demo-ok": { verifyOnCheck: 3 },
  "demo-mismatch": { mismatchOnCheck: 2 },
  "demo-slow": { deviceOnline: false },
  "demo-expired": { expired: true },
  "demo-paid": { paid: true },
  "demo-one": { verifyOnCheck: 3, operators: [ALL_OPERATORS[0]] },
  // Spec 07a: the merchant rejected the claim by hand.
  "demo-rejected": { rejected: true },
};

// Test TrxIDs (decision D21). They are valid for bKash / Nagad / Upay.
const USED_TRX = "USED1234";
const RATE_TRX = "RATE1234";
const NETWORK_ERROR_TRX = "NETERR12";
const SLOW_TRX = "SLOW1234";
const SLOW_MS = 15000;

/**
 * A fresh mock server. [now] is the clock (tests pass a fake one); [latencyMs] makes each answer a little slow
 * so the "পাঠানো হচ্ছে…" state is visible in the browser.
 */
export function createMockApi({ now = () => Date.now(), latencyMs = 0 } = {}) {
  const sessions = new Map();

  const wait = (ms) => (ms > 0 ? new Promise((r) => setTimeout(r, ms)) : Promise.resolve());

  function load(token) {
    if (typeof token !== "string" || !Object.hasOwn(TOKENS, token)) return null;
    let s = sessions.get(token);
    if (!s) {
      const cfg = TOKENS[token];
      const t = now();
      s = {
        cfg,
        statusChecks: 0,
        session: {
          token,
          merchantName: "নমুনা স্টোর",
          orderRef: "#1045",
          amountPoisha: 125000,
          expiresAt: new Date(cfg.expired ? t - MINUTE : t + 30 * MINUTE).toISOString(),
          status: cfg.expired ? "expired" : cfg.paid ? "verified" : cfg.rejected ? "rejected" : "open",
          operators: (cfg.operators ?? ALL_OPERATORS).map((o) => ({ ...o })),
          attemptsLeft: cfg.paid || cfg.rejected ? START_ATTEMPTS - 1 : START_ATTEMPTS,
          returnUrl: "https://example.com/orders/1045",
          deviceOnline: cfg.deviceOnline ?? true,
          submittedOperator: cfg.paid || cfg.rejected ? "bkash" : null,
          submittedTrxId: cfg.paid ? "9K48X7Z2" : cfg.rejected ? "8H22K9P1" : null,
          verifiedAt: cfg.paid ? new Date(t - 5 * MINUTE).toISOString() : null,
        },
      };
      sessions.set(token, s);
    }
    // Open or pending sessions expire when their time is up.
    const ss = s.session;
    if ((ss.status === "open" || ss.status === "pending") && now() >= Date.parse(ss.expiresAt)) ss.status = "expired";
    return s;
  }

  const copy = (session) => structuredClone(session);

  async function getSession(token) {
    await wait(latencyMs);
    const s = load(token);
    return s ? copy(s.session) : { error: "notFound" };
  }

  async function submitClaim(token, operator, trxId) {
    await wait(latencyMs);
    const s = load(token);
    if (!s) return { result: "notFound", session: null };
    const ss = s.session;
    if (ss.status === "expired") return { result: "expired", session: copy(ss) };
    // A claim on a finished session changes nothing; the page shows the current status.
    if (ss.status === "verified" || ss.status === "mismatch" || ss.status === "rejected") {
      return { result: "accepted", session: copy(ss) };
    }

    const trx = normalizeTrxId(trxId);
    const offered = ss.operators.some((o) => o.operator === operator);
    if (!offered || !isValidTrxId(operator, trx)) return { result: "invalidFormat", session: copy(ss) };
    if (trx === RATE_TRX) return { result: "rateLimited", session: copy(ss) };
    if (trx === NETWORK_ERROR_TRX) throw new TypeError("Failed to fetch");
    if (ss.attemptsLeft <= 0) return { result: "noAttemptsLeft", session: copy(ss) };
    if (trx === SLOW_TRX) await wait(SLOW_MS);

    ss.attemptsLeft -= 1;
    if (trx === USED_TRX) return { result: "alreadyUsed", session: copy(ss) };
    ss.status = "pending";
    ss.submittedOperator = operator;
    ss.submittedTrxId = trx;
    s.statusChecks = 0;
    return { result: "accepted", session: copy(ss) };
  }

  async function getStatus(token) {
    await wait(latencyMs);
    const s = load(token);
    if (!s) return { error: "notFound" };
    const ss = s.session;
    if (ss.status === "pending") {
      s.statusChecks += 1;
      if (s.cfg.verifyOnCheck && s.statusChecks >= s.cfg.verifyOnCheck) {
        ss.status = "verified";
        ss.verifiedAt = new Date(now()).toISOString();
      } else if (s.cfg.mismatchOnCheck && s.statusChecks >= s.cfg.mismatchOnCheck) {
        ss.status = "mismatch";
      }
    }
    return copy(ss);
  }

  return { getSession, submitClaim, getStatus };
}

/** The instance the page uses (a short delay so the busy state can be seen). */
export const mockApi = createMockApi({ latencyMs: 400 });
