import assert from "node:assert/strict";
import { moneyTextToPoisha } from "../_shared/money_text.ts";

Deno.test("money_text: the spec examples", () => {
  assert.equal(moneyTextToPoisha("1250.00"), 125000);
  assert.equal(moneyTextToPoisha("1250.5"), 125050);
  assert.equal(moneyTextToPoisha("1250"), 125000);
});

Deno.test("money_text: more valid values", () => {
  assert.equal(moneyTextToPoisha("0.5"), 50);
  assert.equal(moneyTextToPoisha("0.05"), 5);
  assert.equal(moneyTextToPoisha("0"), 0);
  assert.equal(moneyTextToPoisha("0.00"), 0);
  assert.equal(moneyTextToPoisha("15340.50"), 1534050);
});

Deno.test("money_text: anything else is refused", () => {
  for (
    const bad of [
      "",
      "-1",
      "-1250.00",
      "1e3",
      "12.345",
      "1,250.00",
      " 1250",
      "1250 ",
      "abc",
      ".5",
      "5.",
      "1250.0.0",
      "+5",
      "NaN",
      "Infinity",
      "99999999999999",
    ]
  ) {
    assert.equal(moneyTextToPoisha(bad), null, bad);
  }
});

Deno.test("money_text: never a fraction of a poisha", () => {
  for (const t of ["0.1", "0.29", "1.99", "1234567.89"]) {
    const p = moneyTextToPoisha(t);
    assert.ok(p !== null && Number.isInteger(p), t);
  }
  assert.equal(moneyTextToPoisha("0.29"), 29); // float math would give 28.999...
});
