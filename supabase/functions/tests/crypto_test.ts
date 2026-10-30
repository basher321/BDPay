import assert from "node:assert/strict";
import * as nodeCrypto from "node:crypto";
import {
  base64ToBytes,
  derToRaw,
  importP256Spki,
  sha256Hex,
  signatureToRaw,
  utf8,
  verifyP256,
} from "../_shared/crypto.ts";
import {
  bytesToBase64,
  newDeviceKey,
  rawToDer,
  signRaw,
} from "./helpers/device_signer.ts";

Deno.test("sha256Hex: known vectors, string and bytes agree", async () => {
  assert.equal(
    await sha256Hex(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  );
  assert.equal(
    await sha256Hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
  assert.equal(await sha256Hex(utf8("৳ ১,২৫০")), await sha256Hex("৳ ১,২৫০"));
});

Deno.test("base64ToBytes: standard base64 only", () => {
  assert.deepEqual(base64ToBytes("AQID"), new Uint8Array([1, 2, 3]));
  assert.deepEqual(base64ToBytes("AQI="), new Uint8Array([1, 2]));
  assert.equal(base64ToBytes("AQ-_"), null); // url-safe alphabet
  assert.equal(base64ToBytes("AQ ID"), null);
  assert.equal(base64ToBytes("A"), null);
});

/** Signs until pick(raw) is true, so DER edge cases are really produced (not hand-made). */
async function signUntil(
  key: CryptoKey,
  pick: (raw: Uint8Array) => boolean,
  max = 5000,
) {
  for (let i = 0; i < max; i++) {
    const text = `case ${i}`;
    const raw = await signRaw(key, text);
    if (pick(raw)) return { raw, text };
  }
  throw new Error("case not found");
}

Deno.test("DER: r or s with the top bit set gets a 0x00 pad and verifies", async () => {
  const k = await newDeviceKey();
  const pub = (await importP256Spki(k.publicKeySpki))!;
  const { raw, text } = await signUntil(
    k.privateKey,
    (r) => (r[0] & 0x80) !== 0,
  );
  const der = rawToDer(raw);
  assert.equal(der[3], 33); // r length 33
  assert.equal(der[4], 0x00);
  assert.deepEqual(derToRaw(der), raw);
  assert.ok(await verifyP256(pub, der, utf8(text)));
});

Deno.test("DER: a short r or s (leading zero byte) round-trips and verifies", async () => {
  const k = await newDeviceKey();
  const pub = (await importP256Spki(k.publicKeySpki))!;
  // r = 00 0x.. : DER r has at most 31 bytes (a top bit in the 2nd byte would bring the pad back).
  const { raw, text } = await signUntil(
    k.privateKey,
    (r) => r[0] === 0 && r[1] < 0x80,
  );
  const der = rawToDer(raw);
  assert.ok(der[3] <= 31, `r length ${der[3]}`);
  assert.deepEqual(derToRaw(der), raw);
  assert.ok(await verifyP256(pub, der, utf8(text)));
});

Deno.test("an independent DER producer (node:crypto, like Java) verifies", async () => {
  const { privateKey, publicKey } = nodeCrypto.generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  const spki = publicKey.export({ type: "spki", format: "der" });
  const text = "sms-ingest\n1761800000000\nabc";
  const der = nodeCrypto.sign("sha256", utf8(text), privateKey); // DER by default
  assert.equal(der[0], 0x30);
  const pub = await importP256Spki(bytesToBase64(new Uint8Array(spki)));
  assert.ok(pub);
  assert.ok(await verifyP256(pub, new Uint8Array(der), utf8(text)));
  assert.ok(!(await verifyP256(pub, new Uint8Array(der), utf8(text + "x"))));
});

Deno.test("raw 64-byte signatures are accepted too", async () => {
  const k = await newDeviceKey();
  const pub = (await importP256Spki(k.publicKeySpki))!;
  const raw = await signRaw(k.privateKey, "hello");
  assert.equal(raw.length, 64);
  assert.deepEqual(signatureToRaw(raw), raw);
  assert.ok(await verifyP256(pub, raw, utf8("hello")));
});

Deno.test("malformed DER is refused, never a crash", async () => {
  const k = await newDeviceKey();
  const pub = (await importP256Spki(k.publicKeySpki))!;
  const raw = await signRaw(k.privateKey, "hello");
  const der = rawToDer(raw);
  const bad: [string, Uint8Array][] = [
    ["wrong tag", new Uint8Array([0x31, ...der.subarray(1)])],
    ["wrong length", new Uint8Array([0x30, der[1] + 1, ...der.subarray(2)])],
    ["trailing byte", new Uint8Array([...der, 0])],
    ["truncated", der.subarray(0, der.length - 1)],
    ["negative r", new Uint8Array([0x30, 6, 0x02, 1, 0x80, 0x02, 1, 0x01])],
    [
      "non-minimal r",
      new Uint8Array([0x30, 7, 0x02, 2, 0x00, 0x01, 0x02, 1, 0x01]),
    ],
    ["zero r", new Uint8Array([0x30, 6, 0x02, 1, 0x00, 0x02, 1, 0x01])],
    [
      "r too long",
      new Uint8Array([
        0x30,
        38,
        0x02,
        33,
        0x01,
        ...new Array(32).fill(1),
        0x02,
        1,
        1,
      ]),
    ],
    ["empty", new Uint8Array()],
  ];
  for (const [name, sig] of bad) {
    assert.equal(derToRaw(sig), null, name);
    assert.equal(await verifyP256(pub, sig, utf8("hello")), false, name);
  }
  assert.equal(signatureToRaw(new Uint8Array(63)), null);
});

Deno.test("importP256Spki: P-256 ok; P-384, RSA and garbage refused", async () => {
  assert.ok(await importP256Spki((await newDeviceKey()).publicKeySpki));
  const p384 = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-384" },
    true,
    ["sign"],
  );
  const rsa = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign"],
  );
  const spki = async (k: CryptoKey) =>
    bytesToBase64(new Uint8Array(await crypto.subtle.exportKey("spki", k)));
  assert.equal(await importP256Spki(await spki(p384.publicKey)), null);
  assert.equal(await importP256Spki(await spki(rsa.publicKey)), null);
  assert.equal(await importP256Spki("bm90IGEga2V5"), null);
  assert.equal(await importP256Spki("not base64!"), null);
  assert.equal(await importP256Spki(""), null);
});
