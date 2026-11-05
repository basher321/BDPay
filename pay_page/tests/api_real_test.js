import assert from "node:assert/strict";
import { createRealApi } from "../api.real.js";

const BASE = "http://test.local/functions/v1";
const SESSION = { token: "tok", status: "open", amountPoisha: 125000 };

/** A stub fetch: records calls and answers with [status, json] (or never answers). */
function stub(status, json, { hang = false } = {}) {
  const calls = [];
  const fetch = (url, init) => {
    calls.push({ url, init });
    if (hang) {
      return new Promise((_, reject) => init.signal.addEventListener("abort", () => reject(new Error("aborted"))));
    }
    return Promise.resolve({
      status,
      json: () => (json === undefined ? Promise.reject(new SyntaxError("no json")) : Promise.resolve(json)),
    });
  };
  return { fetch, calls };
}

const api = (s, opts = {}) => createRealApi({ base: BASE, fetch: s.fetch, timeoutMs: 50, ...opts });

Deno.test("GET 200 -> the Session; the token is URL-encoded; GET with no body", async () => {
  const s = stub(200, SESSION);
  assert.deepEqual(await api(s).getSession("a b&c"), SESSION);
  assert.equal(s.calls[0].url, `${BASE}/pay-session?t=a%20b%26c`);
  assert.equal(s.calls[0].init.method, "GET");
  assert.equal(s.calls[0].init.body, undefined);
  assert.equal(s.calls[0].init.credentials, "omit");
});

Deno.test("getStatus is the same GET", async () => {
  const s = stub(200, SESSION);
  assert.deepEqual(await api(s).getStatus("tok"), SESSION);
  assert.equal(s.calls[0].init.method, "GET");
});

Deno.test("GET 404 -> {error: notFound}", async () => {
  assert.deepEqual(await api(stub(404, { ok: false })).getSession("tok"), { error: "notFound" });
});

Deno.test("GET 429 -> thrown (the screen stays, the next poll retries)", async () => {
  await assert.rejects(() => api(stub(429, { error: "rateLimited" })).getStatus("tok"));
});

Deno.test("GET 500 and bad JSON -> thrown (network error message)", async () => {
  await assert.rejects(() => api(stub(500, { error: "internal" })).getSession("tok"));
  await assert.rejects(() => api(stub(200, undefined)).getSession("tok"));
});

Deno.test("GET timeout -> aborted and thrown", async () => {
  const s = stub(200, SESSION, { hang: true });
  await assert.rejects(() => api(s).getSession("tok"));
  assert.equal(s.calls[0].init.signal.aborted, true);
});

Deno.test("POST 200 -> {result, session}; JSON body with token, operator, trxId", async () => {
  const s = stub(200, { result: "accepted", session: SESSION });
  assert.deepEqual(await api(s).submitClaim("tok", "bkash", "9K48X7Z2"), { result: "accepted", session: SESSION });
  assert.equal(s.calls[0].url, `${BASE}/pay-session`);
  assert.equal(s.calls[0].init.method, "POST");
  assert.equal(s.calls[0].init.headers["content-type"], "application/json");
  assert.deepEqual(JSON.parse(s.calls[0].init.body), { token: "tok", operator: "bkash", trxId: "9K48X7Z2" });
});

Deno.test("POST 429 -> {result: rateLimited}; POST 404 -> {result: notFound}", async () => {
  assert.deepEqual(await api(stub(429, {})).submitClaim("t", "bkash", "X"), { result: "rateLimited" });
  assert.deepEqual(await api(stub(404, {})).submitClaim("t", "bkash", "X"), { result: "notFound" });
});

Deno.test("POST 500, a 200 without result, and a timeout -> thrown", async () => {
  await assert.rejects(() => api(stub(500, {})).submitClaim("t", "bkash", "X"));
  await assert.rejects(() => api(stub(200, { ok: true })).submitClaim("t", "bkash", "X"));
  await assert.rejects(() => api(stub(200, {}, { hang: true })).submitClaim("t", "bkash", "X"));
});

Deno.test("empty API_BASE -> thrown without any request", async () => {
  const s = stub(200, SESSION);
  await assert.rejects(() => createRealApi({ base: "", fetch: s.fetch }).getSession("tok"));
  assert.equal(s.calls.length, 0);
});
