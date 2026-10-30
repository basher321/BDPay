import assert from "node:assert/strict";
import { assertLocal, testDbEnabled } from "./integration/local_guard.ts";

Deno.test("assertLocal accepts localhost, 127.0.0.1 and [::1]", () => {
  for (
    const url of [
      "http://localhost:54321",
      "http://127.0.0.1:54321",
      "http://[::1]:54321",
      "https://localhost",
    ]
  ) {
    assert.ok(assertLocal(url), url);
  }
});

Deno.test("assertLocal refuses remote, look-alike, missing and odd URLs", () => {
  for (
    const url of [
      "https://abcdefgh.supabase.co",
      "http://localhost.example.com:54321",
      "http://127.0.0.1.nip.io:54321",
      "http://10.0.0.5:54321",
      "http://user@evil.example:54321",
      "ftp://localhost",
      "localhost:54321",
      "",
      undefined,
    ]
  ) {
    assert.throws(() => assertLocal(url), /^Error: refusing/, String(url));
  }
});

Deno.test("the refusal message never contains the URL", () => {
  try {
    assertLocal("https://secret-project.supabase.co");
    assert.fail("should refuse");
  } catch (e) {
    assert.ok(!String(e).includes("secret-project"));
  }
});

Deno.test("without --allow-env the database tests are off", () => {
  assert.equal(testDbEnabled(), false);
});
