// The API the screens use: getSession, submitClaim, getStatus (spec 07 contract).
// Every call has a 10-second timeout; a timeout or any failure becomes a NetworkError.
import { mockApi } from "./api.mock.js";
import { realApi } from "./api.real.js";
import { USE_MOCK } from "./config.js";
import { withTimeout } from "./logic.js";

const TIMEOUT_MS = 10000;

export class NetworkError extends Error {
  constructor() {
    super("network");
    this.name = "NetworkError";
  }
}

function implementation() {
  return USE_MOCK ? mockApi : realApi;
}

async function call(name, ...args) {
  try {
    return await withTimeout(implementation()[name](...args), TIMEOUT_MS);
  } catch {
    // The error itself is never shown: the page only shows its own fixed text.
    throw new NetworkError();
  }
}

/** Session, or {error: "notFound"}. */
export const getSession = (token) => call("getSession", token);

/** {result, session}. */
export const submitClaim = (token, operator, trxId) => call("submitClaim", token, operator, trxId);

/** Session, or {error: "notFound"}. */
export const getStatus = (token) => call("getStatus", token);
