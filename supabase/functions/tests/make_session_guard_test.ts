// Spec 13a rule 6: make_session.ts refuses unless SUPABASE_URL is local, before any network call. Money is
// parsed as whole poisha without float math.
import assert from "node:assert/strict";
import {
  main,
  parseAmountPoisha,
  type SessionBackend,
} from "../../scripts/make_session.ts";

const ARGS = [
  "--email",
  "Owner@Example.com",
  "--amount",
  "1500.00",
  "--order",
  "#T1",
];

function fakeBackend() {
  const calls: string[] = [];
  const backend = (): SessionBackend => {
    calls.push("backend");
    return {
      findMerchantIdByEmail: (email) => {
        calls.push(`find ${email}`);
        return Promise.resolve("m1");
      },
      createSession: (f) => {
        calls.push(`create ${f.merchantId} ${f.amountPoisha} ${f.orderRef}`);
        return Promise.resolve({ token: "tok123" });
      },
    };
  };
  return { calls, backend };
}

const env =
  (url?: string, page = "http://127.0.0.1:8080/index.html") => (k: string) =>
    k === "SUPABASE_URL" ? url : k === "PAY_PAGE_URL" ? page : undefined;

Deno.test("make_session: a remote or missing SUPABASE_URL is refused before any backend call", async () => {
  for (
    const url of [
      undefined,
      "",
      "https://abcdefgh.supabase.co",
      "http://localhost.example.com:54321",
    ]
  ) {
    const f = fakeBackend();
    await assert.rejects(main(env(url), ARGS, f.backend), /^Error: refusing/);
    assert.deepEqual(f.calls, [], String(url));
  }
});

Deno.test("make_session: a remote PAY_PAGE_URL is refused too", async () => {
  const f = fakeBackend();
  await assert.rejects(
    main(
      env("http://127.0.0.1:54321", "https://pay.example.com/"),
      ARGS,
      f.backend,
    ),
    /refusing/,
  );
  assert.deepEqual(f.calls, []);
});

Deno.test("make_session: local -> session for 150000 poisha; prints the pay URL and the emulator form", async () => {
  const f = fakeBackend();
  const lines = await main(env("http://127.0.0.1:54321"), ARGS, f.backend);
  assert.deepEqual(f.calls, [
    "backend",
    "find owner@example.com",
    "create m1 150000 #T1",
  ]);
  assert.deepEqual(lines, [
    "http://127.0.0.1:8080/index.html?t=tok123",
    "http://10.0.2.2:8080/index.html?t=tok123",
  ]);
});

Deno.test("make_session: without spec 09 / 12a it stops with 'not available'", async () => {
  await assert.rejects(
    main(env("http://127.0.0.1:54321"), ARGS),
    /not available/,
  );
});

Deno.test("make_session: amounts are whole poisha; bad ones refused", () => {
  assert.equal(parseAmountPoisha("1500.00"), 150000);
  assert.equal(parseAmountPoisha("1500"), 150000);
  assert.equal(parseAmountPoisha("1600.5"), 160050);
  assert.equal(parseAmountPoisha("0.01"), 1);
  for (
    const bad of [
      "1,500.00",
      "15.555",
      "-1",
      "0",
      "0.00",
      "1e3",
      "",
      "abc",
      " 12. ",
    ]
  ) {
    assert.equal(parseAmountPoisha(bad), null, bad);
  }
});
