// Spec 14: every real SMS sample in tests/real_sms/ (repo root) gives its expected result on the server:
// filterSms keeps or drops it, and a kept one parses to the expected fields (a kept SMS that does not parse
// would be stored as parseFailed). Failure messages name the file and field, never the SMS text or values.
import assert from "node:assert/strict";
import rulesJson from "../_shared/parser_rules.json" with { type: "json" };
import { filterSms, loadRules, parseSms } from "../_shared/parser.ts";

const rules = loadRules(rulesJson);
const dir = new URL("../../../tests/real_sms/", import.meta.url);

const names: string[] = [];
try {
  for await (const e of Deno.readDir(dir)) if (e.isFile) names.push(e.name);
} catch (e) {
  if (!(e instanceof Deno.errors.NotFound)) throw e;
}
names.sort();
const nameSet = new Set(names);

Deno.test(`tests/real_sms holds only .sms + .expected.json pairs (${names.length} files)`, () => {
  for (const n of names) {
    const ok = n.endsWith(".sms")
      ? nameSet.has(`${n.slice(0, -4)}.expected.json`)
      : n.endsWith(".expected.json")
      ? nameSet.has(`${n.slice(0, -14)}.sms`)
      : false;
    assert.ok(ok, `${n}: unpaired or unknown file`);
  }
});

interface Expected {
  keep: boolean;
  operator?: string;
  trxId?: string;
  amountPoisha?: number;
  payerNumber?: string | null;
  kind?: string;
}

for (const n of names.filter((x) => x.endsWith(".sms"))) {
  const id = n.slice(0, -4);
  Deno.test(`real sample ${id}`, async () => {
    const exp = JSON.parse(
      await Deno.readTextFile(new URL(`${id}.expected.json`, dir)),
    ) as Expected;
    const text = (await Deno.readTextFile(new URL(n, dir))).replaceAll(
      "\r\n",
      "\n",
    );
    const cut = text.endsWith("\n") ? text.slice(0, -1) : text;
    const nl = cut.indexOf("\n");
    assert.ok(nl > 0, `${id}: no body line`);
    const sender = cut.slice(0, nl);
    const body = cut.slice(nl + 1);
    const f = filterSms(rules, sender, body);
    if (!exp.keep) {
      assert.ok(f.result !== "keep", `${id}: kept but expected drop`);
      return;
    }
    assert.ok(f.result === "keep", `${id}: not kept`);
    const p = parseSms(sender, body, rules);
    assert.ok(p.ok, `${id}: does not parse`);
    assert.ok(p.operator === exp.operator, `${id}: operator differs`);
    assert.ok(p.trxId === exp.trxId, `${id}: trxId differs`);
    assert.ok(
      p.amountPoisha === exp.amountPoisha,
      `${id}: amountPoisha differs`,
    );
    assert.ok(p.payerNumber === exp.payerNumber, `${id}: payerNumber differs`);
    assert.ok(p.kind === exp.kind, `${id}: kind differs`);
  });
}
