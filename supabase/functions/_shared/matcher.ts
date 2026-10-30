// Spec 08 Matcher interface. NoopMatcher keeps every stored SMS pending; spec 09 replaces it.

import type { SmsRecord, VerifyStatus } from "./types.ts";

export interface MatchOutcome {
  verifyStatus: VerifyStatus;
  serverMessage: string | null;
}

export interface Matcher {
  onSmsStored(sms: SmsRecord): Promise<MatchOutcome>;
}

export class NoopMatcher implements Matcher {
  onSmsStored(_sms: SmsRecord): Promise<MatchOutcome> {
    return Promise.resolve({ verifyStatus: "pending", serverMessage: null });
  }
}
