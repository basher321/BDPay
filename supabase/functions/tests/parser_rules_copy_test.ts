// Needs read permission: deno test --allow-read supabase/functions/tests (plan D77).
import assert from "node:assert/strict";

const here = new URL(".", import.meta.url);
const SERVER = new URL("../_shared/parser_rules.json", here);
const APP = new URL(
  "../../../app/android/app/src/main/res/raw/parser_rules.json",
  here,
);

Deno.test("_shared/parser_rules.json equals the app's copy byte for byte", async () => {
  const [server, app] = await Promise.all([
    Deno.readFile(SERVER),
    Deno.readFile(APP),
  ]);
  assert.ok(app.length > 0);
  assert.deepEqual(server, app);
});
