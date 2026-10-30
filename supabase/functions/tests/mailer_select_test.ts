// Spec 15: mailer selection - BDPAY_FAKE_MAILER=1 -> FakeMailer; RESEND_API_KEY (+ ALERT_FROM_EMAIL) -> ResendMailer;
// neither -> FakeMailer and one "mailerNotConfigured" log line holding no values.
import assert from "node:assert/strict";
import type { LogEntry } from "../_shared/http.ts";
import { FakeMailer, mailerFromEnv, ResendMailer } from "../_shared/mailer.ts";

const KEY = "re_select_test_not_real";
const FROM = "alerts@example.com";

function pick(env: Record<string, string | undefined>) {
  const logs: LogEntry[] = [];
  const mailer = mailerFromEnv((k) => env[k], (e) => logs.push(e));
  return { mailer, logs };
}

Deno.test("BDPAY_FAKE_MAILER=1 -> FakeMailer, even with a Resend key; nothing logged", () => {
  const { mailer, logs } = pick({
    BDPAY_FAKE_MAILER: "1",
    RESEND_API_KEY: KEY,
    ALERT_FROM_EMAIL: FROM,
  });
  assert.ok(mailer instanceof FakeMailer);
  assert.deepEqual(logs, []);
});

Deno.test("RESEND_API_KEY and ALERT_FROM_EMAIL -> ResendMailer; nothing logged", () => {
  const { mailer, logs } = pick({
    RESEND_API_KEY: KEY,
    ALERT_FROM_EMAIL: FROM,
  });
  assert.ok(mailer instanceof ResendMailer);
  assert.deepEqual(logs, []);
});

Deno.test("neither (or a key without a from address) -> FakeMailer + one mailerNotConfigured line", () => {
  for (
    const env of [{}, { RESEND_API_KEY: KEY }, {
      RESEND_API_KEY: "  ",
      ALERT_FROM_EMAIL: FROM,
    }]
  ) {
    const { mailer, logs } = pick(env);
    assert.ok(mailer instanceof FakeMailer);
    assert.deepEqual(logs, [{
      fn: "mailer",
      requestId: "startup",
      code: "mailerNotConfigured",
      merchantId: null,
    }]);
    assert.ok(
      !JSON.stringify(logs).includes(KEY) &&
        !JSON.stringify(logs).includes(FROM),
    );
  }
});
