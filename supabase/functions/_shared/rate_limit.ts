// Rate limiting (spec 09 names this file; spec 15's health is its first user). Handlers depend on the RateLimiter
// interface only. The real one (spec 09 / 12: one atomic hit_rate_limit call per window in the database) comes
// with the Postgres store; MemoryRateLimiter is for tests and the local FakeStore mode only - it does not hold
// across Edge Function instances.

export interface RateLimiter {
  /** Counts one hit for [key] in the current window; true while the count is at most [limit]. */
  hit(key: string, limit: number, windowSeconds: number): Promise<boolean>;
}

export class MemoryRateLimiter implements RateLimiter {
  private readonly counts = new Map<string, number>();

  constructor(private readonly now: () => number = Date.now) {}

  hit(key: string, limit: number, windowSeconds: number): Promise<boolean> {
    const window = Math.floor(this.now() / (windowSeconds * 1000));
    const k = `${key}|${windowSeconds}|${window}`;
    const n = (this.counts.get(k) ?? 0) + 1;
    this.counts.set(k, n);
    return Promise.resolve(n <= limit);
  }
}

/** Spec 09: the Store's atomic counter (hit_rate_limit in the database) as a RateLimiter. */
export function storeLimiter(store: {
  hitRateLimit(
    key: string,
    limit: number,
    windowSeconds: number,
  ): Promise<boolean>;
}): RateLimiter {
  return {
    hit: (key, limit, windowSeconds) =>
      store.hitRateLimit(key, limit, windowSeconds),
  };
}

/** When RATE_LIMIT_PEPPER is not set: a random pepper per worker (buckets then hold per instance only). */
const fallbackPepper = crypto.getRandomValues(new Uint8Array(32));

/**
 * A rate-limit key for a client IP: HMAC-SHA-256(pepper, ip) in hex - never the raw IP and never a plain hash,
 * which could be reversed by trying all addresses (plan 09 D29).
 */
export async function ipKey(
  prefix: string,
  ip: string,
  pepper?: string,
): Promise<string> {
  const keyBytes = pepper ? new TextEncoder().encode(pepper) : fallbackPepper;
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    [
      "sign",
    ],
  );
  const mac = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(ip)),
  );
  return `${prefix}:${
    Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("")
  }`;
}

/** The first address in x-forwarded-for (set by the Supabase edge), else "unknown". */
export function clientIp(req: Request): string {
  const first = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return first !== undefined && first !== "" ? first : "unknown";
}
