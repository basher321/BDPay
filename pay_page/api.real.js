// Spec 13: the spec 07 API on the spec 09 pay-session Edge Function.
// GET  {base}/pay-session?t=TOKEN               -> Session | 404 notFound | 429 = wait (thrown, the poll retries)
// POST {base}/pay-session {token, operator, trxId} -> {result, session} | 429 rateLimited | 404 notFound
// Anything else, or no answer within 10 s, is thrown; api.js turns every throw into its NetworkError.
// Nothing is logged; the token never leaves this module except in the request itself.
import { API_BASE } from "./config.js";

const TIMEOUT_MS = 10000;

/** A real API for one base URL. Tests pass a stub fetch and a short timeout. */
export function createRealApi({ base = API_BASE, fetch = (...a) => globalThis.fetch(...a), timeoutMs = TIMEOUT_MS } = {}) {
  async function request(method, url, body) {
    if (!base) throw new Error("not configured");
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetch(url, {
        method,
        headers: body === undefined ? {} : { "content-type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: ctrl.signal,
        credentials: "omit",
        cache: "no-store",
      });
      let json = null;
      try {
        json = await res.json();
      } catch {
        json = null;
      }
      return { status: res.status, json };
    } finally {
      clearTimeout(timer);
    }
  }

  async function getSession(token) {
    const r = await request("GET", `${base}/pay-session?t=${encodeURIComponent(token)}`);
    if (r.status === 200 && r.json && typeof r.json === "object") return r.json;
    if (r.status === 404) return { error: "notFound" };
    throw new Error(`status ${r.status}`); // 429 included: keep the screen, the next poll tries again
  }

  async function submitClaim(token, operator, trxId) {
    const r = await request("POST", `${base}/pay-session`, { token, operator, trxId });
    if (r.status === 200 && r.json && typeof r.json.result === "string") return r.json;
    if (r.status === 429) return { result: "rateLimited" };
    if (r.status === 404) return { result: "notFound" };
    throw new Error(`status ${r.status}`);
  }

  return { getSession, getStatus: getSession, submitClaim };
}

export const realApi = createRealApi();
