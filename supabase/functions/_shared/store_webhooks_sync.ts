// Spec 17 store-webhooks-sync (every 5 minutes by the schedule; header X-Cron-Secret = CRON_SECRET).
// POST {} -> retries up to 50 due webhook deliveries -> {done, retried, failed}.

import { cronAllowed } from "./claims_expire.ts";
import { type Deps, replier } from "./http.ts";
import {
  fetchSender,
  WebhookDelivery,
  type WebhookSender,
} from "./webhook_notifier.ts";

export const FN = "store-webhooks-sync";
export const BATCH = 50;

export function makeHandler(send: WebhookSender = fetchSender) {
  return async function handle(req: Request, deps: Deps): Promise<Response> {
    const reply = replier(FN, req, deps.log);
    if (req.method !== "POST") return reply.fail(405, "methodNotAllowed");
    if (!cronAllowed(req, deps.config?.cronSecret)) {
      return reply.fail(401, "badCronSecret");
    }
    const delivery = new WebhookDelivery(
      deps.store,
      send,
      deps.config?.payTokenSecret,
      deps.now,
    );
    const due = await deps.store.listDueOrderSyncs(
      new Date(deps.now()).toISOString(),
      BATCH,
    );
    const counts = { done: 0, retried: 0, failed: 0 };
    for (const sync of due) {
      // Only syncs of API connections; Shopify syncs (spec 10) are left for shopify-sync.
      const session = await deps.store.getSession(sync.sessionId);
      const conn = session === null
        ? null
        : await deps.store.getConnection(session.storeId);
      if (conn !== null && conn.kind !== "api") continue;
      counts[await delivery.attempt(sync)]++;
    }
    return reply.ok(counts, null);
  };
}

export const handle = makeHandler();
