// Spec 10: the Shopify Admin client. Errors carry a fixed code (and an HTTP status) only - never a response body,
// a token or a URL with secrets - so nothing secret can reach a log or a response through an error.
import { isValidShopDomain } from "./shopify_auth.ts";

export interface ShopifyTokens {
  accessToken: string;
  /** ISO 8601 UTC. */
  accessExpiresAt: string;
  refreshToken: string;
  /** ISO 8601 UTC. */
  refreshExpiresAt: string;
}

export type ShopifyErrorCode =
  | "invalidShop"
  | "invalidGrant"
  | "unauthorized"
  | "rateLimited"
  | "server"
  | "network"
  | "badRequest"
  | "badResponse"
  | "reconnectNeeded";

export class ShopifyError extends Error {
  constructor(
    readonly code: ShopifyErrorCode,
    readonly status: number | null = null,
  ) {
    super(code);
    this.name = "ShopifyError";
  }
}

/** GraphQL errors reduced to their codes (Shopify's message text is dropped). */
export interface GraphqlResult {
  data: unknown;
  errors: { code: string }[] | null;
}

export interface ShopifyClient {
  exchangeCode(shop: string, code: string): Promise<ShopifyTokens>;
  refresh(shop: string, refreshToken: string): Promise<ShopifyTokens>;
  graphql(
    shop: string,
    accessToken: string,
    query: string,
    variables: Record<string, unknown>,
  ): Promise<GraphqlResult>;
}

export interface FetchClientConfig {
  apiKey: string;
  apiSecret: string;
  apiVersion: string;
  now?: () => number;
  fetchFn?: typeof fetch;
  timeoutMs?: number;
}

function checkShop(shop: string): void {
  if (!isValidShopDomain(shop)) throw new ShopifyError("invalidShop");
}

function errorFor(status: number): ShopifyError {
  if (status === 429) return new ShopifyError("rateLimited", status);
  if (status >= 500) return new ShopifyError("server", status);
  if (status === 401 || status === 403) {
    return new ShopifyError("unauthorized", status);
  }
  return new ShopifyError("badRequest", status);
}

/** The real client (fetch). Shop domains are checked before any request, so no other host is ever called. */
export class FetchShopifyClient implements ShopifyClient {
  readonly #cfg: Required<FetchClientConfig>;

  constructor(cfg: FetchClientConfig) {
    this.#cfg = {
      now: () => Date.now(),
      fetchFn: fetch,
      timeoutMs: 8000,
      ...cfg,
    };
  }

  async #post(url: string, headers: Record<string, string>, body: unknown) {
    try {
      return await this.#cfg.fetchFn(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...headers },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(this.#cfg.timeoutMs),
      });
    } catch {
      throw new ShopifyError("network");
    }
  }

  async #tokenCall(shop: string, body: Record<string, unknown>) {
    checkShop(shop);
    const res = await this.#post(
      `https://${shop}/admin/oauth/access_token`,
      { Accept: "application/json" },
      {
        client_id: this.#cfg.apiKey,
        client_secret: this.#cfg.apiSecret,
        ...body,
      },
    );
    let json: Record<string, unknown> | null = null;
    try {
      json = await res.json();
    } catch {
      json = null;
    }
    if (!res.ok) {
      if (
        (res.status === 400 || res.status === 401) &&
        json?.error === "invalid_grant"
      ) {
        throw new ShopifyError("invalidGrant", res.status);
      }
      throw errorFor(res.status);
    }
    const access = json?.access_token;
    const refresh = json?.refresh_token;
    const accessIn = json?.expires_in;
    const refreshIn = json?.refresh_token_expires_in;
    if (
      typeof access !== "string" || typeof refresh !== "string" ||
      typeof accessIn !== "number" || typeof refreshIn !== "number"
    ) {
      throw new ShopifyError("badResponse", res.status);
    }
    const now = this.#cfg.now();
    return {
      accessToken: access,
      accessExpiresAt: new Date(now + accessIn * 1000).toISOString(),
      refreshToken: refresh,
      refreshExpiresAt: new Date(now + refreshIn * 1000).toISOString(),
    };
  }

  /** Authorization code -> an expiring offline token pair (expiring=1). */
  exchangeCode(shop: string, code: string): Promise<ShopifyTokens> {
    return this.#tokenCall(shop, { code, expiring: 1 });
  }

  /** Refresh -> a NEW pair (the old refresh token stops working). */
  refresh(shop: string, refreshToken: string): Promise<ShopifyTokens> {
    return this.#tokenCall(shop, {
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    });
  }

  async graphql(
    shop: string,
    accessToken: string,
    query: string,
    variables: Record<string, unknown>,
  ): Promise<GraphqlResult> {
    checkShop(shop);
    const res = await this.#post(
      `https://${shop}/admin/api/${this.#cfg.apiVersion}/graphql.json`,
      { "X-Shopify-Access-Token": accessToken },
      { query, variables },
    );
    if (!res.ok) throw errorFor(res.status);
    let json: { data?: unknown; errors?: unknown } | null;
    try {
      json = await res.json();
    } catch {
      throw new ShopifyError("badResponse", res.status);
    }
    const errors = Array.isArray(json?.errors)
      ? json.errors.map((e) => ({
        code: String(
          (e as { extensions?: { code?: unknown } })?.extensions?.code ??
            "unknown",
        ),
      }))
      : null;
    if (errors?.some((e) => e.code === "THROTTLED")) {
      throw new ShopifyError("rateLimited", res.status);
    }
    return { data: json?.data ?? null, errors };
  }
}

/** What the refresh rule needs from the store (spec 12 implements it on the real token vault). */
export interface TokenStore {
  getShopifyTokens(storeId: string): Promise<ShopifyTokens | null>;
  /** Saves [next] only if the stored refresh token is still [oldRefreshToken]; else "changed" (decision D39). */
  swapShopifyTokens(
    storeId: string,
    oldRefreshToken: string,
    next: ShopifyTokens,
  ): Promise<"ok" | "changed">;
  setStoreLastError(
    storeId: string,
    code: "reconnectNeeded" | null,
  ): Promise<void>;
}

export const REFRESH_MARGIN_MS = 5 * 60 * 1000;

/**
 * Returns an access token that is good for at least 5 more minutes, refreshing first when needed.
 * - Another request refreshed at the same time ("changed" or an invalid grant on an old token): use its pair.
 * - Invalid grant and nobody else refreshed: lastError reconnectNeeded, throw reconnectNeeded.
 * - Refresh failed for another reason but the current token has not expired yet: use the current token.
 */
export async function withFreshToken(
  deps: { tokens: TokenStore; client: ShopifyClient; now: () => number },
  store: { id: string; shopDomain: string },
): Promise<string> {
  const current = await deps.tokens.getShopifyTokens(store.id);
  if (!current) throw new ShopifyError("reconnectNeeded");
  const expiresAt = Date.parse(current.accessExpiresAt);
  if (expiresAt - deps.now() >= REFRESH_MARGIN_MS) return current.accessToken;

  let next: ShopifyTokens;
  try {
    next = await deps.client.refresh(store.shopDomain, current.refreshToken);
  } catch (e) {
    if (e instanceof ShopifyError && e.code === "invalidGrant") {
      const latest = await deps.tokens.getShopifyTokens(store.id);
      if (latest && latest.refreshToken !== current.refreshToken) {
        return latest.accessToken; // someone else refreshed first
      }
      await deps.tokens.setStoreLastError(store.id, "reconnectNeeded");
      throw new ShopifyError("reconnectNeeded");
    }
    if (expiresAt > deps.now()) return current.accessToken;
    throw e;
  }
  const swapped = await deps.tokens.swapShopifyTokens(
    store.id,
    current.refreshToken,
    next,
  );
  if (swapped === "changed") {
    const latest = await deps.tokens.getShopifyTokens(store.id);
    if (latest) return latest.accessToken;
    throw new ShopifyError("reconnectNeeded");
  }
  return next.accessToken;
}
