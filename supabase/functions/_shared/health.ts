// Spec 15 health (no auth; for the uptime monitor): GET -> 200 {ok: true, db: true, time} when a simple Store
// read works, else 503 {ok: false, db: false}. No user data. Rate limit 60 per minute per IP hash (never the raw
// IP). Logs only the fixed entry.

import { sha256Hex, utf8 } from "./crypto.ts";
import { type Deps, error, json, requestIdOf } from "./http.ts";

export const FN = "health";
export const HEALTH_LIMIT = 60;
export const HEALTH_WINDOW_SECONDS = 60;

const NO_STORE = { "Cache-Control": "no-store" };

function withHeaders(res: Response): Response {
  for (const [k, v] of Object.entries(NO_STORE)) res.headers.set(k, v);
  return res;
}

/** The first address in x-forwarded-for (set by the Supabase edge), else "unknown" (all such callers share one bucket). */
function clientIp(req: Request): string {
  const first = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return first !== undefined && first !== "" ? first : "unknown";
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const requestId = requestIdOf(req);
  const done = (code: string, res: Response) => {
    deps.log({ fn: FN, requestId, code, merchantId: null });
    return withHeaders(res);
  };
  if (req.method !== "GET") {
    return done(
      "methodNotAllowed",
      json(405, {
        ok: false,
        error: "methodNotAllowed",
        message: "Only GET is allowed.",
      }),
    );
  }
  // Plan 15 D212: without a shared limiter health does not answer (an unlimited database read per request).
  if (deps.limiter === undefined) {
    return done("rateLimiterMissing", json(503, { ok: false, db: false }));
  }
  const key = `health:${await sha256Hex(utf8(clientIp(req)))}`;
  if (!(await deps.limiter.hit(key, HEALTH_LIMIT, HEALTH_WINDOW_SECONDS))) {
    return done("rateLimited", error(429, "rateLimited"));
  }
  try {
    await deps.store.getParserRules(); // plan 15 D211: the active rules always exist after runbook step 2
  } catch {
    return done("dbDown", json(503, { ok: false, db: false }));
  }
  return done(
    "ok",
    json(200, { ok: true, db: true, time: new Date(deps.now()).toISOString() }),
  );
}
