// Spec 09 pay-session (public API for the pay page). GET ?t=TOKEN (or header X-Pay-Token, plan 09 D34) -> Session;
// POST {token, operator, trxId} -> {result, session}. CORS only for PAY_PAGE_ORIGIN. Never logs the token, TrxID
// or IP (the IP is only used as an HMAC'd rate-limit key).

import { corsHeaders, withHeaders } from "./cors.ts";
import {
  type Deps,
  isObject,
  json,
  parseJson,
  readBody,
  requestIdOf,
} from "./http.ts";
import { evaluate } from "./match_rules.ts";
import { NoopNotifier, notifySafely } from "./notifier.ts";
import { clientIp, ipKey } from "./rate_limit.ts";
import {
  loadSessionJson,
  type SessionJson,
  visibleStatus,
} from "./session_view.ts";
import { hashToken, isTokenShaped } from "./token.ts";
import { isValidTrxId, normalizeTrxId } from "./trx_format.ts";
import { type Operator, OPERATORS, type PaymentSession } from "./types.ts";

export const FN = "pay-session";
export const GET_LIMIT = 60; // per minute per token
export const POST_LIMIT = 20; // per 10 minutes per client IP

export type PostResult =
  | "accepted"
  | "invalidFormat"
  | "alreadyUsed"
  | "noAttemptsLeft"
  | "expired"
  | "notFound"
  | "rateLimited";

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const requestId = requestIdOf(req);
  const cors = corsHeaders(req, deps.config?.payPageOrigin);
  const done = (
    code: string,
    res: Response,
    merchantId: string | null = null,
  ) => {
    deps.log({ fn: FN, requestId, code, merchantId });
    res.headers.set("Cache-Control", "no-store");
    return withHeaders(res, cors);
  };
  if (req.method === "OPTIONS") {
    return done("preflight", new Response(null, { status: 204 }));
  }
  if (req.method === "GET") return await get(req, deps, done);
  if (req.method === "POST") return await post(req, deps, done);
  return done(
    "methodNotAllowed",
    json(405, {
      ok: false,
      error: "methodNotAllowed",
      message: "Only GET, POST and OPTIONS are allowed.",
    }),
  );
}

type Done = (
  code: string,
  res: Response,
  merchantId?: string | null,
) => Response;

const NOT_FOUND = { ok: false, error: "notFound", message: "Not found." };

async function get(req: Request, deps: Deps, done: Done): Promise<Response> {
  const token = new URL(req.url).searchParams.get("t") ??
    req.headers.get("X-Pay-Token");
  if (!isTokenShaped(token)) return done("notFound", json(404, NOT_FOUND));
  const tokenHash = await hashToken(token);
  if (!(await deps.store.hitRateLimit(`pay-get:${tokenHash}`, GET_LIMIT, 60))) {
    return done(
      "rateLimited",
      json(429, {
        ok: false,
        error: "rateLimited",
        message: "Too many requests.",
      }),
    );
  }
  const session = await deps.store.getSessionByTokenHash(tokenHash);
  if (session === null) return done("notFound", json(404, NOT_FOUND));
  const view = await loadSessionJson(deps.store, token, session, deps.now());
  return done("ok", json(200, view), session.merchantId);
}

function reply(
  done: Done,
  result: PostResult,
  session: SessionJson | null,
  merchantId: string | null,
  status = 200,
): Response {
  return done(result, json(status, { result, session }), merchantId);
}

async function post(req: Request, deps: Deps, done: Done): Promise<Response> {
  const now = deps.now();
  // a. 20 per 10 minutes per client IP (HMAC key, never the raw IP).
  const ipK = await ipKey(
    "pay-post",
    clientIp(req),
    deps.config?.rateLimitPepper,
  );
  if (!(await deps.store.hitRateLimit(ipK, POST_LIMIT, 600))) {
    return reply(done, "rateLimited", null, null, 429);
  }
  const raw = await readBody(req, 4096);
  const body = raw === null ? undefined : parseJson(raw);
  if (
    !isObject(body) || !isTokenShaped(body.token) ||
    typeof body.operator !== "string" ||
    typeof body.trxId !== "string" || body.trxId.length > 64
  ) {
    return done(
      "badRequest",
      json(400, {
        ok: false,
        error: "badRequest",
        message: "The request body is not valid.",
      }),
    );
  }
  const token = body.token;
  const view = (s: PaymentSession) =>
    loadSessionJson(deps.store, token, s, deps.now());

  // b. The session and its state.
  const session = await deps.store.getSessionByTokenHash(
    await hashToken(token),
  );
  if (session === null) return reply(done, "notFound", null, null);
  const m = session.merchantId;
  const shown = visibleStatus(session, now);
  if (shown === "expired") {
    return reply(done, "expired", await view(session), m);
  }
  if (shown === "verified" || shown === "mismatch" || shown === "rejected") {
    return reply(done, "accepted", await view(session), m);
  }

  // c. Format and offered operator (no attempt used).
  const operator = body.operator as Operator;
  const trxId = normalizeTrxId(body.trxId);
  const offered = (await deps.store.listActiveWallets(m)).some((w) =>
    w.operator === operator
  );
  if (
    !OPERATORS.includes(operator) || !offered || !isValidTrxId(operator, trxId)
  ) {
    return reply(done, "invalidFormat", await view(session), m);
  }

  // d. The same TrxID as the active claim: nothing changes, no attempt used.
  if (session.activeClaimId !== null) {
    const active = await deps.store.getClaim(session.activeClaimId);
    if (
      active !== null && active.operator === operator && active.trxId === trxId
    ) {
      return reply(done, "accepted", await view(session), m);
    }
  }

  // e. No attempts left.
  if (session.attemptsLeft <= 0) {
    return reply(done, "noAttemptsLeft", await view(session), m);
  }

  // f. Live on another session -> alreadyUsed (one attempt used).
  const live = await deps.store.findLiveClaimByTrx(m, operator, trxId);
  if (live !== null && live.sessionId !== session.id) {
    await deps.store.spendAttempt(session.id);
    return reply(
      done,
      "alreadyUsed",
      await view((await deps.store.getSession(session.id))!),
      m,
    );
  }

  // g. The claim (one transaction).
  const submitted = await deps.store.submitClaim({
    sessionId: session.id,
    operator,
    trxId,
  });
  if ("conflict" in submitted) {
    const fresh = (await deps.store.getSession(session.id))!;
    const result: PostResult = submitted.conflict === "noAttemptsLeft"
      ? "noAttemptsLeft"
      : submitted.conflict === "closed" &&
          visibleStatus(fresh, deps.now()) === "expired"
      ? "expired"
      : submitted.conflict === "closed"
      ? "accepted"
      : "alreadyUsed";
    return reply(done, result, await view(fresh), m);
  }

  // h. An SMS that already arrived.
  const claim = submitted.claim;
  const sms = await deps.store.findUnmatchedSms(m, operator, trxId);
  if (
    sms !== null && sms.operator !== null && sms.trxId !== null &&
    sms.amountPoisha !== null
  ) {
    const pending = (await deps.store.getSession(session.id))!;
    const decision = evaluate(pending, claim, {
      merchantId: sms.merchantId,
      operator: sms.operator,
      trxId: sms.trxId,
      amountPoisha: sms.amountPoisha,
      status: sms.status,
      receivedAt: sms.receivedAt,
    });
    if (decision.result === "verified") {
      const r = await deps.store.recordVerified({
        claimId: claim.id,
        smsId: sms.id,
        method: "auto",
        userId: null,
        note: null,
      });
      if (r === "ok") {
        const verified = (await deps.store.getSession(session.id))!;
        await notifySafely(
          deps.notifier ?? new NoopNotifier(),
          verified,
          deps.log,
          FN,
          requestIdOf(req),
        );
      }
    } else if (decision.result === "mismatch") {
      await deps.store.recordMismatch({
        claimId: claim.id,
        smsId: sms.id,
        reason: decision.reason,
      });
    }
  }

  // i. Accepted with the fresh session.
  return reply(
    done,
    "accepted",
    await view((await deps.store.getSession(session.id))!),
    m,
  );
}
