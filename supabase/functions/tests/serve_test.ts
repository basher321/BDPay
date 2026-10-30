import assert from "node:assert/strict";
import { depsFromEnv } from "../_shared/fake_store.ts";
import { type LogEntry, serveFunction } from "../_shared/http.ts";
import { FN, handle } from "../_shared/ingest.ts";
import { world } from "./helpers/world.ts";

Deno.test("without BDPAY_FAKE_STORE -> 503 storeNotReady", async () => {
  const logs: LogEntry[] = [];
  const serve = serveFunction(
    FN,
    handle,
    () => depsFromEnv(() => undefined),
    (e) => logs.push(e),
  );
  const res = await serve(
    new Request("http://localhost/sms-ingest", { method: "POST", body: "{}" }),
  );
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), {
    ok: false,
    error: "storeNotReady",
    message: "The data store is not ready.",
  });
  assert.equal(logs[0].code, "storeNotReady");
});

Deno.test("with BDPAY_FAKE_STORE=1 the handler runs (unsigned -> 401)", async () => {
  const serve = serveFunction(
    FN,
    handle,
    () => depsFromEnv((k) => (k === "BDPAY_FAKE_STORE" ? "1" : undefined)),
    () => {},
  );
  const res = await serve(
    new Request("http://localhost/sms-ingest", { method: "POST", body: "{}" }),
  );
  assert.equal(res.status, 401);
});

Deno.test("a throwing handler -> 500 internalError with a fixed message; the error is not logged", async () => {
  const logs: LogEntry[] = [];
  const w = world();
  const serve = serveFunction(
    "x",
    () => Promise.reject(new Error("TrxID 9K48X7Z2 from 01712345678")),
    () => w.deps,
    (e) => logs.push(e),
  );
  const res = await serve(
    new Request("http://localhost/x", { method: "POST" }),
  );
  assert.equal(res.status, 500);
  const text = await res.text();
  assert.ok(!text.includes("9K48X7Z2"));
  assert.equal(JSON.parse(text).error, "internalError");
  assert.deepEqual(Object.keys(logs[0]).sort(), [
    "code",
    "fn",
    "merchantId",
    "requestId",
  ]);
  assert.ok(!JSON.stringify(logs).includes("9K48X7Z2"));
});

Deno.test("non-POST -> 405 through the wrapper", async () => {
  const w = world();
  const serve = serveFunction(FN, handle, () => w.deps, () => {});
  const res = await serve(new Request("http://localhost/sms-ingest"));
  assert.equal(res.status, 405);
});

Deno.test("request id: a sane platform id is used; header junk is replaced", async () => {
  const logs: LogEntry[] = [];
  const w = world();
  w.deps.log = (e) => logs.push(e);
  await handle(
    new Request("http://localhost/sms-ingest", {
      headers: { "sb-request-id": "abc-123" },
    }),
    w.deps,
  );
  await handle(
    new Request("http://localhost/sms-ingest", {
      headers: { "sb-request-id": "TrxID 9K48X7Z2" },
    }),
    w.deps,
  );
  assert.equal(logs[0].requestId, "abc-123");
  assert.notEqual(logs[1].requestId, "TrxID 9K48X7Z2");
  assert.match(logs[1].requestId, /^[0-9a-f-]{36}$/);
});
