// Spec 10a: pure view logic for the BDPay pay box. No imports, so Deno can test it directly.

export type PaylinkResult =
  | { status: "ready"; payUrl: string; sessionStatus: string }
  | { status: "notBdpay" }
  | { status: "alreadyPaid" }
  | { status: "notReady" }
  | { status: "error" };

export type View =
  | "hidden"
  | "loading"
  | "payNow"
  | "pending"
  | "paid"
  | "waitLonger"
  | "failed";

export const RETRY_DELAY_MS = 3000;
/** notReady: loading while attempt < 10, then waitLonger. */
export const NOT_READY_LIMIT = 10;
/** error: loading for attempts 0 and 1, then failed. */
export const ERROR_LIMIT = 2;

/**
 * Which view to show for the answer to call number [attempt] (0 = the first call).
 * "paid" comes only from the backend's answer (alreadyPaid, or ready + verified).
 * An unknown sessionStatus is hidden (never a pay button).
 */
export function decideView(result: PaylinkResult, attempt: number): View {
  switch (result.status) {
    case "notBdpay":
      return "hidden";
    case "alreadyPaid":
      return "paid";
    case "ready":
      switch (result.sessionStatus) {
        case "verified":
          return "paid";
        case "open":
          return "payNow";
        case "pending":
        case "mismatch":
          return "pending";
        default: // expired, rejected (the pay page explains them) and anything unknown
          return "hidden";
      }
    case "notReady":
      return attempt < NOT_READY_LIMIT ? "loading" : "waitLonger";
    case "error":
      return attempt < ERROR_LIMIT ? "loading" : "failed";
    default:
      return "hidden";
  }
}

/** Milliseconds before the next call, or null when no retry is due (decision D48: it needs the result too). */
export function nextRetryDelay(
  result: PaylinkResult,
  attempt: number,
): number | null {
  return decideView(result, attempt) === "loading" ? RETRY_DELAY_MS : null;
}

/** Only https links without user info are opened. */
export function isSafePayUrl(url: unknown): url is string {
  if (typeof url !== "string") return false;
  try {
    const u = new URL(url);
    return u.protocol === "https:" && u.username === "" && u.password === "";
  } catch {
    return false;
  }
}

/**
 * The shopify-paylink answer -> PaylinkResult. Reads ONLY status, payUrl and sessionStatus; every other field
 * (for example an amount or a wallet number) is dropped. Anything unexpected is "error".
 */
export function parsePaylinkAnswer(
  httpStatus: number,
  body: unknown,
): PaylinkResult {
  if (httpStatus !== 200 || body === null || typeof body !== "object") {
    return { status: "error" };
  }
  const b = body as {
    status?: unknown;
    payUrl?: unknown;
    sessionStatus?: unknown;
  };
  switch (b.status) {
    case "ready":
      if (isSafePayUrl(b.payUrl) && typeof b.sessionStatus === "string") {
        return {
          status: "ready",
          payUrl: b.payUrl,
          sessionStatus: b.sessionStatus,
        };
      }
      return { status: "error" };
    case "notBdpay":
    case "alreadyPaid":
    case "notReady":
      return { status: b.status };
    default:
      return { status: "error" };
  }
}
