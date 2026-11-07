// Spec 14 (plan 14 D185, D191, D200, D201): repeatable searches over the whole project.
// - no secret-shaped values, keys or real phone numbers in any text file;
// - ops/e2e_queries.sql is read-only and selects no SMS text, numbers, tokens or notes;
// - ops/staging_runbook.txt keeps secrets out of files and history, lists the right --no-verify-jwt functions,
//   and every step ends with a "check:" paragraph;
// - tests/e2e/E2E_CHECKLIST.txt holds A-P and an empty results table;
// - every rule in both parser_rules.json files carries the same version.
// Failures name the file and the kind of finding only - never the matched text. .env* files, keystores and
// key.properties are never opened (CLAUDE.md).
import assert from "node:assert/strict";

const root = new URL("../../../", import.meta.url);
const SKIP_DIRS = new Set([
  ".git",
  "build",
  ".dart_tool",
  "node_modules",
  ".gradle",
  ".idea",
  ".kotlin",
  ".cxx",
]);
const BINARY =
  /\.(png|jpe?g|gif|webp|ico|apk|aab|jar|so|zip|gz|docx|pdf|woff2?|ttf|otf|keystore|jks|class|lock|bin)$/i;
const NEVER_OPEN = (name: string) =>
  name.startsWith(".env") || name === "key.properties" ||
  /\.(jks|keystore)$/i.test(name);
const SELF = "supabase/functions/tests/repo_scan_test.ts";

async function textFiles(): Promise<{ path: string; text: string }[]> {
  const out: { path: string; text: string }[] = [];
  async function walk(dir: URL, rel: string) {
    for await (const e of Deno.readDir(dir)) {
      const path = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory) {
        if (!SKIP_DIRS.has(e.name)) {
          await walk(new URL(`${e.name}/`, dir), path);
        }
      } else if (e.isFile && !NEVER_OPEN(e.name) && !BINARY.test(e.name)) {
        const url = new URL(e.name, dir);
        if ((await Deno.stat(url)).size > 2_000_000) continue;
        out.push({ path, text: await Deno.readTextFile(url) });
      }
    }
  }
  await walk(root, "");
  return out;
}

const files = await textFiles();
const read = (path: string) => files.find((f) => f.path === path)?.text;

// ---- secrets and keys ----

// Built from parts so this file does not match itself.
const SECRET_PATTERNS: [string, RegExp][] = [
  [
    "jwt",
    new RegExp(
      "ey" + "J[A-Za-z0-9_-]{10,}\\.ey" +
        "J[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}",
    ),
  ],
  ["supabase secret key", new RegExp("sb_" + "secret_[A-Za-z0-9_-]{10,}")],
  [
    "supabase publishable key",
    new RegExp("sb_" + "publishable_[A-Za-z0-9_-]{10,}"),
  ],
  ["shopify token", new RegExp("shp" + "(at|ca|ss|pa)_[A-Fa-f0-9]{16,}")],
  ["private key", new RegExp("-----BEGIN [A-Z ]*PRIVATE " + "KEY-----")],
  ["resend key", new RegExp("\\bre" + "_[A-Za-z0-9_]{20,}")],
  [
    "secret assignment",
    new RegExp(
      "(SECRET|API_KEY|SERVICE_ROLE_KEY|ANON_KEY|ACCESS_TOKEN|PASSWORD)\\s*[:=]\\s*[\"']?[A-Za-z0-9+/_=-]{24,}",
    ),
  ],
];

const FIXTURE = /not[-_]real|fake|dummy|example|placeholder/i;

Deno.test(`no secret, key or token values in ${files.length} project text files`, () => {
  const found: string[] = [];
  for (const f of files) {
    if (f.path === SELF) continue;
    for (const [kind, re] of SECRET_PATTERNS) {
      const hits = [...f.text.matchAll(new RegExp(re.source, "g"))];
      // A test fixture whose value says it is fake (for example "test-app-secret-not-real") is not a secret.
      if (hits.some((h) => !FIXTURE.test(h[0]))) {
        found.push(`${f.path}: ${kind}`);
      }
    }
  }
  assert.deepEqual(found, []);
});

// ---- phone numbers ----

const PHONE = /(?<![0-9])(?:\+?880)?01[3-9][0-9]{8,9}(?![0-9])/g;
/** D185: the only numbers real SMS samples may contain. */
function isFake(n: string): boolean {
  const m = /^(?:\+?880)?(017000000|0170000000)([0-9]{2})$/.exec(n);
  return m !== null && Number(m[2]) >= 1 && Number(m[2]) <= 99;
}
/** Made-up numbers already used by earlier specs' tests, mocks and docs (kept rather than rewriting old tests). */
const MADE_UP = new Set([
  "01700000000",
  "01711000000",
  "01711111111",
  "01711222333",
  "01711223344",
  "01712345678",
  "01798765432",
  "01799999999",
  "01811222333",
  "01812345678",
  "01911002200",
  "01999999999",
  "017112223331",
  "017123456780",
  "017123456781",
  "017123456782",
  "017123456789",
  "019876543211",
]);

Deno.test("phone numbers: only fake-list numbers in tests/real_sms, only known made-up numbers elsewhere", () => {
  const found: string[] = [];
  for (const f of files) {
    if (f.path === SELF) continue;
    const sample = f.path.startsWith("tests/real_sms/");
    for (const m of f.text.matchAll(PHONE)) {
      const n = m[0].replace(/^\+?880/, "0").replace(/^00/, "0");
      const ok = isFake(m[0]) || isFake(n) || (!sample && MADE_UP.has(n));
      if (!ok) {
        found.push(
          `${f.path}: ${
            sample ? "number not on the fake list" : "unknown phone number"
          }`,
        );
      }
    }
  }
  assert.deepEqual([...new Set(found)], []);
});

// ---- ops/e2e_queries.sql ----

const stripSql = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/--[^\n]*/g, " ");

Deno.test("e2e_queries.sql: SELECT only, no side effects, none of the private columns, no *", () => {
  const sql = read("ops/e2e_queries.sql");
  assert.ok(sql !== undefined, "ops/e2e_queries.sql exists");
  const code = stripSql(sql).toLowerCase();
  const statements = code.split(";").map((s) => s.trim()).filter((s) =>
    s !== ""
  );
  assert.ok(statements.length >= 5, "at least the five query groups");
  for (const [i, s] of statements.entries()) {
    assert.ok(/^(select|with)\b/.test(s), `statement ${i + 1}: not a SELECT`);
  }
  const forbiddenWords =
    /\b(insert|update|delete|merge|truncate|drop|alter|create|grant|revoke|copy|call|vacuum|refresh|lock|comment|execute|do|listen|notify|reset|set)\b/;
  assert.ok(!forbiddenWords.test(code), "a data- or setting-changing keyword");
  assert.ok(
    !/\b(cron|net|vault|private|dblink|extensions)\s*\./.test(code),
    "a side-effect schema",
  );
  assert.ok(
    !/\b(set_config|pg_sleep|pg_terminate_backend|pg_cancel_backend|lo_\w+)\s*\(/
      .test(code),
    "a side-effect function",
  );
  const columns =
    /\b(body|payer_number|trx_id|sender|token_hash|token_secret_id|public_key_spki|install_id|wallet_number|details|email|note|data|decrypted_secret)\b/;
  assert.ok(!columns.test(code), "a private column");
  assert.ok(!/(select|,)\s*(\w+\.)?\*/.test(code), "select *");
});

// ---- ops/staging_runbook.txt and ops/production_runbook.txt ----

/** Plan 14 section 2 (staging); production adds health (spec 15). */
const NO_VERIFY_JWT: Record<string, boolean> = {
  "sms-ingest": true,
  "device-heartbeat": true,
  "device-deactivate": true,
  "parser-rules": true,
  "sms-status": true,
  "pay-session": true,
  "shopify-oauth-callback": true,
  "shopify-webhooks": true,
  "shopify-paylink": true,
  "claims-expire": true,
  "shopify-sync": true,
  "alerts-check": true,
  "device-register": false,
  "claim-review": false,
  "shopify-connect-link": false,
  "shopify-status": false,
  "alerts-list": false,
  "merchant-api": true,
  "store-webhooks-sync": true,
  "store-connections": false,
};
const PROD_NO_VERIFY_JWT: Record<string, boolean> = {
  ...NO_VERIFY_JWT,
  health: true,
};

const RUNBOOKS: {
  path: string;
  steps: number;
  deploy: Record<string, boolean>;
}[] = [
  { path: "ops/staging_runbook.txt", steps: 9, deploy: NO_VERIFY_JWT },
  { path: "ops/production_runbook.txt", steps: 11, deploy: PROD_NO_VERIFY_JWT },
];

/** The lines a person types: indented by exactly 4 spaces. */
const commandLines = (text: string) =>
  text.split("\n").filter((l) => /^ {4}\S/.test(l)).map((l) => l.trim());

Deno.test("runbooks: the deploy lists match the plans and cover every function folder", async () => {
  for (const rbk of RUNBOOKS) {
    const rb = read(rbk.path);
    assert.ok(rb !== undefined, `${rbk.path} exists`);
    const deployed: Record<string, boolean> = {};
    for (
      const m of rb.matchAll(
        /^ {4}supabase functions deploy (\S+)( --no-verify-jwt)?\s*$/gm,
      )
    ) {
      assert.ok(!(m[1] in deployed), `${rbk.path}: ${m[1]} deployed twice`);
      deployed[m[1]] = m[2] !== undefined;
    }
    assert.deepEqual(deployed, rbk.deploy, rbk.path);
  }
  for await (const e of Deno.readDir(new URL("supabase/functions/", root))) {
    if (e.isDirectory && e.name !== "_shared" && e.name !== "tests") {
      assert.ok(
        e.name in PROD_NO_VERIFY_JWT,
        `${e.name}: function folder missing from the production runbook list`,
      );
    }
  }
});

Deno.test("runbooks: steps in order, each ending with a check: paragraph", () => {
  for (const rbk of RUNBOOKS) {
    const rb = read(rbk.path)!;
    const heads = [...rb.matchAll(/^STEP (\d+) - /gm)];
    assert.deepEqual(
      heads.map((h) => Number(h[1])),
      Array.from({ length: rbk.steps }, (_, i) => i + 1),
      rbk.path,
    );
    for (const [i, h] of heads.entries()) {
      const end = i + 1 < heads.length
        ? heads[i + 1].index!
        : rb.indexOf("\nAFTER THE RUNBOOK");
      const section = rb.slice(h.index!, end > 0 ? end : undefined);
      const paragraphs = section.split(/\n\s*\n/).map((p) => p.trim()).filter((
        p,
      ) => p !== "");
      assert.ok(
        /^check:/m.test(paragraphs.at(-1)!),
        `${rbk.path} step ${h[1]}: does not end with a check: paragraph`,
      );
    }
  }
});

Deno.test("runbooks: secrets never typed on a command line or written to a file; no seed push; unlink at the end", () => {
  const SECRET_NAMES =
    "PAY_TOKEN_SECRET|CRON_SECRET|SHOPIFY_API_KEY|SHOPIFY_API_SECRET|SUPABASE_SERVICE_ROLE_KEY|SUPABASE_ANON_KEY|RESEND_API_KEY";
  const literal = new RegExp(`(${SECRET_NAMES})=(?!\\$)`);
  for (const rbk of RUNBOOKS) {
    const commands = commandLines(read(rbk.path)!);
    for (const c of commands) {
      const where = `${rbk.path}: `;
      assert.ok(
        !literal.test(c),
        where + "a secret value typed on a command line",
      );
      assert.ok(!/--env-file/.test(c), where + "--env-file in a command");
      assert.ok(
        !(/^supabase link/.test(c) && /(\s-p\b|--password)/.test(c)),
        where + "a password on supabase link",
      );
      assert.ok(!/--include-seed/.test(c), where + "seed pushed");
      assert.ok(!/decrypted_secrets/.test(c), where + "a decrypted Vault read");
      assert.ok(
        !/-(storepass|keypass)\s/.test(c),
        where + "a keystore password on the command line",
      );
      assert.ok(
        !(/key\.properties/.test(c) &&
          /(Set-Content|Add-Content|Out-File|echo|>)/.test(c)),
        where + "key.properties written by a command",
      );
    }
    assert.ok(
      commands.includes("supabase unlink"),
      `${rbk.path}: no unlink after the online steps`,
    );
  }
});

Deno.test("ops files: no command deletes data", () => {
  for (
    const path of [
      "ops/staging_runbook.txt",
      "ops/production_runbook.txt",
      "ops/incident_playbook.txt",
    ]
  ) {
    const text = read(path);
    assert.ok(text !== undefined, `${path} exists`);
    for (const c of commandLines(text)) {
      assert.ok(
        !/\b(delete\s+from|drop\s|truncate\s)/i.test(c),
        `${path}: a SQL delete / drop / truncate`,
      );
      assert.ok(!/supabase\s+db\s+reset/.test(c), `${path}: db reset`);
      assert.ok(
        !/Remove-Item(?!\s+Env:)/.test(c),
        `${path}: Remove-Item on files`,
      );
      assert.ok(!/flutter\s+clean/.test(c), `${path}: flutter clean`);
      assert.ok(!/\brm\s+-|rmdir/.test(c), `${path}: rm / rmdir`);
    }
  }
});

Deno.test("release checklist: the 9 go / no-go lines, each yes / no; incident playbook: the 7 cases", () => {
  const rc = read("ops/release_checklist.txt")!;
  const lines = rc.split("\n").filter((l) =>
    l.startsWith("[ ] yes  [ ] no   ")
  );
  assert.equal(lines.length, 9);
  for (
    const needle of [
      "Spec 14 checklist",
      "untested operators turned off",
      "Production secrets are all new",
      "Advisors show no errors",
      "health is green",
      "reviewed by a lawyer",
      "Keystore backed up offline",
      "One full real payment",
      "Support contact",
    ]
  ) {
    assert.ok(lines.some((l) => l.includes(needle)), needle);
  }
  const pb = read("ops/incident_playbook.txt")!;
  assert.deepEqual(
    [...pb.matchAll(/^CASE (\d) - /gm)].map((m) => Number(m[1])),
    [1, 2, 3, 4, 5, 6, 7],
  );
  // The only data changes in the playbook are the single-row device revoke and its audit entry.
  const sql = commandLines(pb).filter((c) => /^(update|insert)\b/i.test(c));
  assert.deepEqual(sql.map((c) => c.split(" ").slice(0, 3).join(" ")), [
    "update public.devices set",
    "insert into public.audit_log",
  ]);
  assert.ok(sql[0].includes("where id = '<old device id>'"));
});

// ---- spec 15: signing file guard and deployment hosts in code ----

Deno.test("build.gradle.kts reads key.properties only for release tasks; the configuration cache stays off", () => {
  const gradle = read("app/android/app/build.gradle.kts")!;
  const loads = [...gradle.matchAll(/keyPropertiesFile\.inputStream\(\)/g)];
  assert.equal(loads.length, 1);
  assert.ok(
    /if \(wantsRelease && keyPropertiesFile\.isFile\) keyPropertiesFile\.inputStream\(\)/
      .test(gradle),
  );
  assert.ok(
    !/signingConfigs\.getByName\("debug"\)/.test(gradle),
    "no debug-key release fallback",
  );
  for (const f of files.filter((x) => x.path.endsWith("gradle.properties"))) {
    assert.ok(
      !/^\s*org\.gradle\.configuration-cache\s*=\s*true/m.test(f.text),
      `${f.path}: configuration cache on`,
    );
  }
});

Deno.test("no keystore or signing file anywhere in the project (names only, never opened)", async () => {
  const found: string[] = [];
  async function walk(dir: URL, rel: string) {
    for await (const e of Deno.readDir(dir)) {
      const path = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory) {
        if (!SKIP_DIRS.has(e.name)) {
          await walk(new URL(`${e.name}/`, dir), path);
        }
      } else if (
        /\.(jks|keystore|p12)$/i.test(e.name) || e.name === "key.properties"
      ) {
        found.push(path);
      }
    }
  }
  await walk(root, "");
  assert.deepEqual(found, []);
});

Deno.test("code holds no deployment hosts (only env names, REPLACE_ME, localhost and provider API endpoints)", () => {
  const CODE = /\.(ts|js|dart|kt|kts|sql|html|toml|json|yaml|yml|xml)$/;
  const HOSTS =
    /\b[a-z]{20}\.supabase\.co\b|\b[a-z0-9-]+\.pages\.dev\b|\bbdpay\.(com|net|org|io|app|xyz|bd|com\.bd)\b(?!\.)/;
  const found: string[] = [];
  for (const f of files) {
    if (f.path === SELF || !CODE.test(f.path) || f.path.startsWith("ops/")) {
      continue;
    }
    if (HOSTS.test(f.text)) found.push(f.path);
  }
  assert.deepEqual(found, []);
});

// ---- tests/e2e/E2E_CHECKLIST.txt ----

Deno.test("checklist: tests A-P and an empty results table", () => {
  const cl = read("tests/e2e/E2E_CHECKLIST.txt");
  assert.ok(cl !== undefined, "tests/e2e/E2E_CHECKLIST.txt exists");
  const letters = "ABCDEFGHIJKLMNOP".split("");
  assert.deepEqual([...cl.matchAll(/^([A-P])\. /gm)].map((m) => m[1]), letters);
  const rows = [...cl.matchAll(/^\| ([A-P]) +\|(.*)$/gm)];
  assert.deepEqual(rows.map((r) => r[1]), letters);
});

// ---- parser rules version (D184) and migrations ----

Deno.test("both parser_rules.json files: one version on every rule", () => {
  for (
    const path of [
      "app/android/app/src/main/res/raw/parser_rules.json",
      "supabase/functions/_shared/parser_rules.json",
    ]
  ) {
    const rules = JSON.parse(read(path)!) as { version: number }[];
    assert.equal(
      new Set(rules.map((r) => r.version)).size,
      1,
      `${path}: mixed versions`,
    );
  }
});

Deno.test("migrations hold no URL and no secret value", () => {
  const migrations = files.filter((f) =>
    f.path.startsWith("supabase/migrations/")
  );
  for (const m of migrations) {
    const code = stripSql(m.text);
    assert.ok(!/:\/\//.test(code), `${m.path}: a URL`);
  }
});
