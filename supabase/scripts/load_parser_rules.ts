// Spec 14: loads supabase/functions/_shared/parser_rules.json as a new active version of the parser_rules table,
// in the database named by SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from this terminal's environment.
// Prints only "<version> loaded" or a short fixed message - never the URL, the key, the rules or a server answer.
//
// Plan 14 D183 (answered "no SQL function"): the switch is done with REST calls through the database API:
//   1. read the existing versions; refuse if this version exists or is not higher than the newest;
//   2. insert the new version inactive; 3. switch the old active version off; 4. switch the new one on
//      (if 4 fails, the old version is switched back on). Between 3 and 4 no version is active for a moment.
// No package is used (plain fetch), so nothing is added to deno.json.
//
// Run (see ops/staging_runbook.txt step 2):
//   deno run --allow-net=<host> --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY \
//     --allow-read=supabase/functions/_shared/parser_rules.json supabase/scripts/load_parser_rules.ts

import { loadRules } from "../functions/_shared/parser.ts";

export type Fetch = (url: string, init: RequestInit) => Promise<Response>;

/** A short message that is safe to print (no URL, key, rules or server text). */
export class LoadError extends Error {}

/** Plan 14 D184: every rule carries the same version; that number is the loaded version. */
export function fileVersion(rules: unknown): number {
  try {
    loadRules(rules); // every pattern must compile, exactly as the server will load them
  } catch {
    throw new LoadError("refusing: parser_rules.json does not load");
  }
  const versions = new Set(
    (rules as { version: unknown }[]).map((r) => r.version),
  );
  const [v] = [...versions];
  if (versions.size !== 1 || !Number.isSafeInteger(v) || (v as number) < 1) {
    throw new LoadError("refusing: every rule must have the same version");
  }
  return v as number;
}

export async function main(
  env: (key: string) => string | undefined,
  rulesText: string,
  fetchFn: Fetch,
): Promise<string> {
  const base = env("SUPABASE_URL")?.replace(/\/+$/, "");
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !key) {
    throw new LoadError(
      "refusing: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set",
    );
  }
  let rules: unknown;
  try {
    rules = JSON.parse(rulesText);
  } catch {
    throw new LoadError("refusing: parser_rules.json is not JSON");
  }
  const version = fileVersion(rules);

  const table = `${base}/rest/v1/parser_rules`;
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
    Prefer: "return=minimal",
  };
  const call = async (step: string, url: string, init: RequestInit) => {
    let res: Response;
    try {
      res = await fetchFn(url, { ...init, headers });
    } catch {
      throw new LoadError(`failed: ${step} (no answer)`);
    }
    if (!res.ok) {
      await res.body?.cancel();
      if (step === "insert" && res.status === 409) {
        throw new LoadError(`refusing: version ${version} already exists`);
      }
      throw new LoadError(`failed: ${step} (HTTP ${res.status})`);
    }
    return res;
  };

  const rows = await (await call("read", `${table}?select=version,is_active`, {
    method: "GET",
  })).json() as { version: number; is_active: boolean }[];
  if (rows.some((r) => r.version === version)) {
    throw new LoadError(`refusing: version ${version} already exists`);
  }
  const newest = Math.max(0, ...rows.map((r) => r.version));
  if (version < newest) {
    throw new LoadError(
      `refusing: version ${version} is lower than ${newest}`,
    );
  }
  const active = rows.find((r) => r.is_active)?.version;

  await call("insert", table, {
    method: "POST",
    body: JSON.stringify({ version, rules, is_active: false }),
  });
  if (active !== undefined) {
    await call("deactivate", `${table}?version=eq.${active}`, {
      method: "PATCH",
      body: JSON.stringify({ is_active: false }),
    });
  }
  try {
    await call("activate", `${table}?version=eq.${version}`, {
      method: "PATCH",
      body: JSON.stringify({ is_active: true }),
    });
  } catch (e) {
    if (active !== undefined) {
      try {
        await call("restore", `${table}?version=eq.${active}`, {
          method: "PATCH",
          body: JSON.stringify({ is_active: true }),
        });
      } catch {
        throw new LoadError(
          `failed: version ${version} inserted but not active, and version ${active} could not be switched back on - fix is_active in Studio now`,
        );
      }
      throw new LoadError(
        `failed: version ${version} inserted but not active; version ${active} is active again`,
      );
    }
    throw e;
  }
  return `${version} loaded`;
}

if (import.meta.main) {
  try {
    const text = await Deno.readTextFile(
      new URL("../functions/_shared/parser_rules.json", import.meta.url),
    );
    console.log(await main((k) => Deno.env.get(k), text, fetch));
  } catch (e) {
    console.error(e instanceof LoadError ? e.message : "failed");
    Deno.exit(1);
  }
}
