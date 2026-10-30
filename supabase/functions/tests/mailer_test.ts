import assert from "node:assert/strict";
import { FakeMailer, type Mailer } from "../_shared/mailer.ts";

const MAIL = { to: "owner@example.test", subject: "BDPay: test", text: "x" };

Deno.test("FakeMailer keeps sent mails in memory", async () => {
  const mailer: Mailer = new FakeMailer();
  assert.equal(await mailer.send(MAIL), "sent");
  assert.deepEqual((mailer as FakeMailer).sent, [MAIL]);
});

Deno.test("FakeMailer stores a copy, not the caller's object", async () => {
  const mailer = new FakeMailer();
  const mail = { ...MAIL };
  await mailer.send(mail);
  mail.subject = "changed";
  assert.equal(mailer.sent[0].subject, "BDPay: test");
});

Deno.test("FakeMailer failing -> 'failed', nothing kept, attempt counted; then works again", async () => {
  const mailer = new FakeMailer();
  mailer.failing = true;
  assert.equal(await mailer.send(MAIL), "failed");
  assert.deepEqual(mailer.sent, []);
  mailer.failing = false;
  assert.equal(await mailer.send(MAIL), "sent");
  assert.equal(mailer.sent.length, 1);
  assert.equal(mailer.attempts, 2);
});
