// Spec 13: which API the page uses.
// USE_MOCK true = the spec 07 mock server (api.mock.js). Default false: the real pay-session API.
export const USE_MOCK = false;

// The Edge Functions URL, for example http://127.0.0.1:54321/functions/v1 for local Supabase (set by hand for local
// testing; the production one comes in spec 15). Left empty here so no server address is committed (plan 13 D145);
// while empty, every call fails with the network error message.
// Also add this URL's origin to connect-src in index.html's Content-Security-Policy.
export const API_BASE = "";
