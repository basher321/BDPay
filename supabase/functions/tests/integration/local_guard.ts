// Spec 12a: tests and smoke scripts refuse any database that is not on this machine. Called before any client is
// made. The message names the rule, never the URL value or a key.

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

export function assertLocal(url: string | undefined): URL {
  if (url === undefined || url === "") {
    throw new Error("refusing: SUPABASE_URL is not set");
  }
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error("refusing: SUPABASE_URL is not a URL");
  }
  if (!LOCAL_HOSTS.has(parsed.hostname)) {
    throw new Error("refusing: not a local database");
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error("refusing: not an http URL");
  }
  return parsed;
}

/** BDPAY_TEST_DB=1, read with a permission check so the unit run (no --allow-env) simply skips. */
export function testDbEnabled(): boolean {
  const state = Deno.permissions.querySync({
    name: "env",
    variable: "BDPAY_TEST_DB",
  });
  return state.state === "granted" && Deno.env.get("BDPAY_TEST_DB") === "1";
}
