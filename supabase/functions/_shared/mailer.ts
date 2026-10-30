// Spec 11 mailer; spec 15 adds ResendMailer and the selection from the environment (mailerFromEnv).
// send() returns only "sent" or "failed": no provider message (which may repeat the address) can reach a log.

export interface Mail {
  to: string;
  subject: string;
  text: string;
}

export type SendResult = "sent" | "failed";

export interface Mailer {
  send(mail: Mail): Promise<SendResult>;
}

/** Keeps sent mails in memory. Set failing = true to act like a provider that is down. */
export class FakeMailer implements Mailer {
  readonly sent: Mail[] = [];
  failing = false;
  attempts = 0;

  send(mail: Mail): Promise<SendResult> {
    this.attempts += 1;
    if (this.failing) return Promise.resolve("failed");
    this.sent.push({ ...mail });
    return Promise.resolve("sent");
  }
}

export type Fetch = (url: string, init: RequestInit) => Promise<Response>;

export const RESEND_ENDPOINT = "https://api.resend.com/emails";
export const RESEND_TIMEOUT_MS = 10_000;

/**
 * Spec 15: sends through the Resend email API. 2xx -> "sent"; any other status, a network error or no answer
 * within 10 s -> "failed". The response body is never read and nothing is logged: the address, subject, body
 * and key never leave this method except in the request to Resend.
 */
export class ResendMailer implements Mailer {
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    private readonly fetchFn: Fetch = fetch,
    private readonly timeoutMs = RESEND_TIMEOUT_MS,
  ) {}

  async send(mail: Mail): Promise<SendResult> {
    try {
      const res = await this.fetchFn(RESEND_ENDPOINT, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: this.from,
          to: [mail.to],
          subject: mail.subject,
          text: mail.text,
        }),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
      await res.body?.cancel();
      return res.status >= 200 && res.status < 300 ? "sent" : "failed";
    } catch {
      return "failed";
    }
  }
}

/**
 * Spec 15 mailer selection (like the store selection): BDPAY_FAKE_MAILER=1 -> FakeMailer; RESEND_API_KEY and
 * ALERT_FROM_EMAIL set -> ResendMailer; otherwise FakeMailer and one "mailerNotConfigured" log line (plan 15 D216,
 * D217). Call once per worker. Env values come in through [get]; nothing about them is logged.
 */
export function mailerFromEnv(
  get: (name: string) => string | undefined,
  log: (entry: {
    fn: string;
    requestId: string;
    code: string;
    merchantId: string | null;
  }) => void,
  fetchFn: Fetch = fetch,
): Mailer {
  if (get("BDPAY_FAKE_MAILER") === "1") return new FakeMailer();
  const key = get("RESEND_API_KEY")?.trim();
  const from = get("ALERT_FROM_EMAIL")?.trim();
  if (key && from) return new ResendMailer(key, from, fetchFn);
  log({
    fn: "mailer",
    requestId: "startup",
    code: "mailerNotConfigured",
    merchantId: null,
  });
  return new FakeMailer();
}
