// Spec 17 store-connections (Supabase user token; the user owns a merchant).
// GET -> {connections}. POST {action: create | updateWebhook | rotateKey | disable, ...}.
// The API key and the webhook secret are returned only by create (and the key by rotateKey), never stored.

import {
  cleanHttpsUrl,
  cleanSiteName,
  hashApiKey,
  isPlatform,
  keyPrefixOf,
  newApiKey,
  publicConnection,
  webhookSecret,
} from "./connections.ts";
import { type Deps, isObject, parseJson, readBody, replier } from "./http.ts";
import type { ConnectionRecord } from "./types.ts";

export const FN = "store-connections";

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const reply = replier(FN, req, deps.log);
  if (req.method !== "GET" && req.method !== "POST") {
    return reply.fail(405, "methodNotAllowed");
  }
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const user = token === "" ? null : await deps.users.verify(token);
  if (user === null) return reply.fail(401, "badUserToken");
  const owner = await deps.store.findMerchantForUser(user.userId);
  if (owner === null) return reply.fail(403, "noMerchant");
  const merchantId = owner.merchantId;

  if (req.method === "GET") {
    const list = await deps.store.listConnections(merchantId);
    return reply.ok({ connections: list.map(publicConnection) }, merchantId);
  }

  const raw = await readBody(req, 8192);
  const body = raw === null ? undefined : parseJson(raw);
  if (!isObject(body) || typeof body.action !== "string") {
    return reply.fail(400, "badRequest", merchantId);
  }
  const secret = deps.config?.payTokenSecret;
  if (!secret) return reply.fail(503, "storeNotReady", merchantId);

  const audit = (action: string, id: string, data: Record<string, string>) =>
    deps.store.writeAudit({
      merchantId,
      actorType: "user",
      actorId: user.userId,
      action,
      entity: "store",
      entityId: id,
      data,
    });

  if (body.action === "create") {
    if (body.platform === "shopify") {
      return reply.fail(400, "useShopifyConnect", merchantId);
    }
    const platform = body.platform;
    if (!isPlatform(platform) || platform === "shopify") {
      return reply.fail(400, "invalidPlatform", merchantId);
    }
    const siteName = cleanSiteName(body.siteName);
    if (siteName === null) return reply.fail(400, "invalidName", merchantId);
    const siteUrl = cleanHttpsUrl(body.siteUrl);
    if (siteUrl === null) return reply.fail(400, "invalidUrl", merchantId);
    const apiKey = newApiKey();
    const made = await deps.store.createApiConnection({
      merchantId,
      platform,
      siteName,
      siteUrl,
      apiKeyPrefix: keyPrefixOf(apiKey),
      apiKeyHash: await hashApiKey(apiKey),
    });
    if (made === "duplicate") return reply.fail(409, "duplicate", merchantId);
    await audit("store.create", made.id, { platform: made.platform });
    return reply.ok({
      connection: publicConnection(made),
      apiKey,
      webhookSecret: await webhookSecret(secret, made.id, made.secretVersion),
    }, merchantId);
  }

  // The other actions work on one of the merchant's own API connections.
  const id = typeof body.id === "string" ? body.id : "";
  const found: ConnectionRecord | null = id === ""
    ? null
    : await deps.store.getConnection(id);
  if (found === null || found.merchantId !== merchantId) {
    return reply.fail(404, "notFound", merchantId);
  }
  if (found.kind !== "api") {
    return reply.fail(400, "useShopifyConnect", merchantId);
  }

  switch (body.action) {
    case "updateWebhook": {
      const url = body.webhookUrl === null || body.webhookUrl === ""
        ? null
        : cleanHttpsUrl(body.webhookUrl);
      if (url === null && body.webhookUrl !== null && body.webhookUrl !== "") {
        return reply.fail(400, "invalidUrl", merchantId);
      }
      const c = await deps.store.updateConnection(found.id, {
        webhookUrl: url,
      });
      await audit("store.updateWebhook", c.id, {
        set: url !== null ? "yes" : "no",
      });
      return reply.ok({ connection: publicConnection(c) }, merchantId);
    }
    case "rotateKey": {
      const apiKey = newApiKey();
      const c = await deps.store.updateConnection(found.id, {
        apiKeyPrefix: keyPrefixOf(apiKey),
        apiKeyHash: await hashApiKey(apiKey),
      });
      await audit("store.rotateKey", c.id, {});
      return reply.ok({ connection: publicConnection(c), apiKey }, merchantId);
    }
    case "disable": {
      const c = await deps.store.updateConnection(found.id, {
        status: "disabled",
      });
      await audit("store.disable", c.id, {});
      return reply.ok({ connection: publicConnection(c) }, merchantId);
    }
    default:
      return reply.fail(400, "badRequest", merchantId);
  }
}
