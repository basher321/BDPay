// Spec 12a: the real UserVerifier. Asks Supabase Auth who owns a user token (works with the project's signing keys,
// legacy or asymmetric). The token is never logged; any failure means "not a valid user".

import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.118.0";
import type { UserVerifier } from "./user_auth.ts";

export class SupabaseUserVerifier implements UserVerifier {
  private readonly db: SupabaseClient;

  constructor(url: string, serviceRoleKey: string) {
    this.db = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  async verify(token: string): Promise<{ userId: string } | null> {
    if (token.length < 20 || token.length > 4096) return null;
    try {
      const { data, error } = await this.db.auth.getUser(token);
      if (error || !data?.user?.id) return null;
      return { userId: data.user.id };
    } catch {
      return null;
    }
  }
}
