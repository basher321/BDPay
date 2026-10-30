// Spec 15: ResendMailer with a stub fetch - 2xx sent, anything else failed, timeout failed, nothing logged.
import assert from "node:assert/strict";
import {
  type Fetch,
  type Mail,
  RESEND_ENDPOINT,
  RESEND_TIMEOUT_MS,
  ResendMailer,
} from "../_shared/mailer.ts";

const KEY = "re_test_not_real_key_value";
const MAIL: Mail = {
  to: "owner@example.com",
  subject: "BDPay: ফোন সংযোগ নেই",
  text: "secret-looking body text 12345",
};

function stub(status: number) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fn: Fetch = (url, init) => {
    calls.push({ url, init });
    return Promise.resolve(
      new Response(`provider said ${MAIL.to}`, { status }),
    );
  };
  return { calls, fn };
}

/** Runs [f] while recording every console call, so a test can show nothing was printed. */
async function quiet<T>(
  f: () => Promise<T>,
): Promise<{ value: T; printed: string[] }> {
  const printed: string[] = [];
  const saved = {
    log: console.log,
    error: console.error,
    warn: console.warn,
    info: console.info,
  };
  const record = (...a: unknown[]) => printed.push(a.map(String).join(" "));
  Object.assign(console, {
    log: record,
    error: record,
    warn: record,
    info: record,
  });
  try {
    return { value: await f(), printed };
  } finally {
    Object.assign(console, saved);
  }
}

Deno.test("ResendMailer: 2xx -> sent; the request is the Resend send-email call", async () => {
  for (const status of [200, 201, 202]) {
    const s = stub(status);
    const { value, printed } = await quiet(() =>
      new ResendMailer(KEY, "BDPay <alerts@example.com>", s.fn).send(MAIL)
    );
    assert.equal(value, "sent");
    assert.deepEqual(printed, []);
    assert.equal(s.calls.length, 1);
    const { url, init } = s.calls[0];
    assert.equal(url, RESEND_ENDPOINT);
    assert.equal(init.method, "POST");
    const headers = init.headers as Record<string, string>;
    assert.equal(headers.Authorization, `Bearer ${KEY}`);
    assert.equal(headers["Content-Type"], "application/json");
    assert.deepEqual(JSON.parse(init.body as string), {
      from: "BDPay <alerts@example.com>",
      to: [MAIL.to],
      subject: MAIL.subject,
      text: MAIL.text,
    });
    assert.ok(init.signal instanceof AbortSignal);
  }
});

Deno.test("ResendMailer: 500, 401, 429 and 3xx -> failed; nothing printed", async () => {
  for (const status of [500, 401, 429, 302]) {
    const { value, printed } = await quiet(() =>
      new ResendMailer(KEY, "a@example.com", stub(status).fn).send(MAIL)
    );
    assert.equal(value, "failed", String(status));
    assert.deepEqual(printed, []);
  }
});

Deno.test("ResendMailer: network error -> failed, the error (with the address and key) never escapes", async () => {
  const throwing: Fetch = () =>
    Promise.reject(new Error(`connect failed for ${MAIL.to} with ${KEY}`));
  const { value, printed } = await quiet(() =>
    new ResendMailer(KEY, "a@example.com", throwing).send(MAIL)
  );
  assert.equal(value, "failed");
  assert.deepEqual(printed, []);
});

Deno.test("ResendMailer: no answer before the timeout -> failed (10 s by default)", async () => {
  assert.equal(RESEND_TIMEOUT_MS, 10_000);
  const hanging: Fetch = (_url, init) =>
    new Promise((_resolve, reject) => {
      init.signal?.addEventListener("abort", () => reject(init.signal?.reason));
    });
  const { value, printed } = await quiet(() =>
    new ResendMailer(KEY, "a@example.com", hanging, 20).send(MAIL)
  );
  assert.equal(value, "failed");
  assert.deepEqual(printed, []);
});
