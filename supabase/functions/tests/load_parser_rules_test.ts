// Spec 14: load_parser_rules.ts. Unit tests with a fake fetch; one local-only integration test (BDPAY_TEST_DB=1)
// that checks the refusal of an existing version and writes nothing (a loaded row can never be deleted).
import assert from "node:assert/strict";
import rulesJson from "../_shared/parser_rules.json" with { type: "json" };
import {
  type Fetch,
  fileVersion,
  LoadError,
  main,
} from "../../scripts/load_parser_rules.ts";
import { assertLocal, testDbEnabled } from "./integration/local_guard.ts";

const URL_ = "https://example-ref.supabase.co";
const KEY = "service-key-SECRET-VALUE";
const env = (k: string) =>
  k === "SUPABASE_URL"
    ? URL_
    : k === "SUPABASE_SERVICE_ROLE_KEY"
    ? KEY
    : undefined;
const rulesText = JSON.stringify(rulesJson);
const version = fileVersion(rulesJson);

interface Call {
  method: string;
  url: string;
  body: string | null;
}

function fakeFetch(
  rows: { version: number; is_active: boolean }[],
  fail: Record<string, number> = {},
) {
  const calls: Call[] = [];
  const fn: Fetch = (url, init) => {
    const method = init.method ?? "GET";
    calls.push({ method, url, body: (init.body as string) ?? null });
    const step = method === "GET"
      ? "read"
      : method === "POST"
      ? "insert"
      : (init.body as string).includes("false")
      ? "deactivate"
      : url.endsWith(`eq.${version}`)
      ? "activate"
      : "restore";
    const status = fail[step] ?? 200;
    const body = step === "read" ? JSON.stringify(rows) : "";
    return Promise.resolve(new Response(body || null, { status }));
  };
  return { calls, fn };
}

async function message(p: Promise<unknown>): Promise<string> {
  try {
    await p;
  } catch (e) {
    assert.ok(e instanceof LoadError, "only LoadError leaves main");
    return e.message;
  }
  throw new Error("expected a refusal");
}

function assertQuiet(text: string) {
  assert.ok(
    !text.includes(KEY) && !text.includes(URL_) &&
      !text.includes("example-ref"),
  );
}

Deno.test("load_parser_rules: missing env -> refusing, no call", async () => {
  const f = fakeFetch([]);
  const msg = await message(main(() => undefined, rulesText, f.fn));
  assert.match(msg, /^refusing: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY/);
  assert.equal(f.calls.length, 0);
});

Deno.test("load_parser_rules: fresh table -> insert inactive, then activate; prints only '<v> loaded'", async () => {
  const f = fakeFetch([]);
  const out = await main(env, rulesText, f.fn);
  assert.equal(out, `${version} loaded`);
  assertQuiet(out);
  assert.deepEqual(f.calls.map((c) => c.method), ["GET", "POST", "PATCH"]);
  const inserted = JSON.parse(f.calls[1].body!);
  assert.equal(inserted.version, version);
  assert.equal(inserted.is_active, false);
  assert.deepEqual(inserted.rules, rulesJson);
  assert.ok(
    f.calls[2].url.endsWith(`/rest/v1/parser_rules?version=eq.${version}`),
  );
});

Deno.test("load_parser_rules: an existing version is refused before any write", async () => {
  const f = fakeFetch([{ version, is_active: true }]);
  const msg = await message(main(env, rulesText, f.fn));
  assert.equal(msg, `refusing: version ${version} already exists`);
  assert.deepEqual(f.calls.map((c) => c.method), ["GET"]);
});

Deno.test("load_parser_rules: a race on insert (409) is refused too", async () => {
  const f = fakeFetch([], { insert: 409 });
  assert.equal(
    await message(main(env, rulesText, f.fn)),
    `refusing: version ${version} already exists`,
  );
});

Deno.test("load_parser_rules: a version lower than the newest is refused", async () => {
  const f = fakeFetch([{ version: version + 5, is_active: true }]);
  assert.match(await message(main(env, rulesText, f.fn)), /is lower than/);
  assert.equal(f.calls.length, 1);
});

Deno.test("load_parser_rules: with an older active version -> insert, old off, new on", async () => {
  const bumped = JSON.stringify(
    (rulesJson as Record<string, unknown>[]).map((r) => ({
      ...r,
      version: version + 1,
    })),
  );
  const f = fakeFetch([{ version, is_active: true }]);
  // fakeFetch names steps by the file version; with the bumped file every PATCH is a plain 200.
  assert.equal(await main(env, bumped, f.fn), `${version + 1} loaded`);
  assert.deepEqual(f.calls.map((c) => c.method), [
    "GET",
    "POST",
    "PATCH",
    "PATCH",
  ]);
  assert.ok(
    f.calls[2].url.endsWith(`version=eq.${version}`) &&
      f.calls[2].body!.includes("false"),
  );
  assert.ok(
    f.calls[3].url.endsWith(`version=eq.${version + 1}`) &&
      f.calls[3].body!.includes("true"),
  );
});

Deno.test("load_parser_rules: activation fails -> the old version is switched back on", async () => {
  const bumped = (rulesJson as Record<string, unknown>[]).map((r) => ({
    ...r,
    version: version + 1,
  }));
  const calls: Call[] = [];
  const fn: Fetch = (url, init) => {
    calls.push({
      method: init.method!,
      url,
      body: (init.body as string) ?? null,
    });
    if (init.method === "GET") {
      return Promise.resolve(
        new Response(JSON.stringify([{ version, is_active: true }])),
      );
    }
    const activating = init.method === "PATCH" &&
      url.endsWith(`eq.${version + 1}`);
    return Promise.resolve(
      new Response(null, { status: activating ? 500 : 200 }),
    );
  };
  const msg = await message(main(env, JSON.stringify(bumped), fn));
  assert.equal(
    msg,
    `failed: version ${
      version + 1
    } inserted but not active; version ${version} is active again`,
  );
  assert.ok(
    calls.at(-1)!.url.endsWith(`eq.${version}`) &&
      calls.at(-1)!.body!.includes("true"),
  );
  assertQuiet(msg);
});

Deno.test("load_parser_rules: errors never carry the URL, key or server text", async () => {
  const throwing: Fetch = () =>
    Promise.reject(new Error(`connect to ${URL_} with ${KEY} failed`));
  const msg = await message(main(env, rulesText, throwing));
  assert.equal(msg, "failed: read (no answer)");
  const serverText: Fetch = () =>
    Promise.resolve(new Response(`bad key ${KEY}`, { status: 401 }));
  const msg2 = await message(main(env, rulesText, serverText));
  assert.equal(msg2, "failed: read (HTTP 401)");
  assertQuiet(msg + msg2);
});

Deno.test("load_parser_rules: rules with mixed versions or bad patterns are refused before any call", async () => {
  const mixed = (rulesJson as Record<string, unknown>[]).map((r, i) => ({
    ...r,
    version: i === 0 ? 2 : 1,
  }));
  const f = fakeFetch([]);
  assert.equal(
    await message(main(env, JSON.stringify(mixed), f.fn)),
    "refusing: every rule must have the same version",
  );
  const broken = structuredClone(rulesJson) as Record<string, unknown>[];
  broken[0].trx = "(";
  assert.equal(
    await message(main(env, JSON.stringify(broken), f.fn)),
    "refusing: parser_rules.json does not load",
  );
  assert.equal(
    await message(main(env, "{oops", f.fn)),
    "refusing: parser_rules.json is not JSON",
  );
  assert.equal(f.calls.length, 0);
});

Deno.test({
  name:
    "load_parser_rules (local database): the loaded version is refused and nothing changes",
  ignore: !testDbEnabled(),
  async fn() {
    const url = assertLocal(Deno.env.get("SUPABASE_URL")).origin; // never a remote database
    const localEnv = (k: string) =>
      k === "SUPABASE_URL" ? url : Deno.env.get(k);
    const read = async () => {
      const res = await fetch(
        `${url}/rest/v1/parser_rules?select=version,is_active&order=version`,
        {
          headers: {
            apikey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
            Authorization: `Bearer ${
              Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
            }`,
          },
        },
      );
      return await res.json();
    };
    const before = await read();
    assert.ok(
      before.some((r: { version: number }) => r.version === version),
      "seed has the file version",
    );
    assert.equal(
      await message(main(localEnv, rulesText, fetch)),
      `refusing: version ${version} already exists`,
    );
    assert.deepEqual(await read(), before);
  },
});
