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
