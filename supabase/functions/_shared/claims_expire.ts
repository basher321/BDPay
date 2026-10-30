// Spec 09 claims-expire (called every 5 minutes by the schedule): header X-Cron-Secret must equal env CRON_SECRET.
// An empty or unset CRON_SECRET refuses every call (fails closed, plan 14 D202). Constant-time compare.

import { type Deps, replier } from "./http.ts";

export const FN = "claims-expire";

/** Same-length constant-time string compare; different lengths -> false. */
export function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

/** True only when a non-empty secret is configured and the header matches it. */
export function cronAllowed(req: Request, secret: string | undefined): boolean {
  const got = req.headers.get("X-Cron-Secret") ?? "";
  return !!secret && got !== "" && safeEqual(got, secret);
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const reply = replier(FN, req, deps.log);
  if (req.method !== "POST") return reply.fail(405, "methodNotAllowed");
  if (!cronAllowed(req, deps.config?.cronSecret)) {
    return reply.fail(401, "badCronSecret");
  }
  const counts = await deps.store.expireDue(new Date(deps.now()).toISOString());
  await deps.store.writeAudit({
    merchantId: null,
    actorType: "system",
    actorId: "claims-expire",
    action: "claims.expire",
    entity: "claims",
    entityId: "batch",
    data: { sessions: counts.sessions, claims: counts.claims },
  });
  return reply.ok({ sessions: counts.sessions, claims: counts.claims }, null);
}
