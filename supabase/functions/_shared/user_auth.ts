// Spec 08 user token check. The real verifier (Supabase Auth) is not in this step; it will live outside the
// handlers. FakeUserVerifier is for tests and BDPAY_FAKE_STORE runs only.

export interface UserVerifier {
  /** The user behind a Supabase user token, or null when the token is not valid. */
  verify(token: string): Promise<{ userId: string } | null>;
}

export class FakeUserVerifier implements UserVerifier {
  constructor(private readonly tokens: ReadonlyMap<string, string>) {}

  verify(token: string): Promise<{ userId: string } | null> {
    const userId = this.tokens.get(token);
    return Promise.resolve(userId === undefined ? null : { userId });
  }
}
