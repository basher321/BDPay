// Spec 15: the site pages (privacy, terms, download) and the pay page footer. Same CSP and no-innerHTML rules as
// spec 07; no outside scripts; layout rules that keep every page usable at 320 px. Needs --allow-read.
import assert from "node:assert/strict";

const dir = new URL("../", import.meta.url);
const read = (name) => Deno.readTextFileSync(new URL(name, dir));
const PAGES = ["index.html", "privacy.html", "terms.html", "download.html"];
const STATIC = ["privacy.html", "terms.html", "download.html"];

const csp = (html) => /<meta http-equiv="Content-Security-Policy" content="([^"]*)">/.exec(html)?.[1];

Deno.test("every page has the index.html CSP and a mobile viewport", () => {
  const expected = csp(read("index.html"));
  assert.ok(expected?.includes("script-src 'self'") && expected.includes("require-trusted-types-for 'script'"));
  for (const page of PAGES) {
    const html = read(page);
    assert.equal(csp(html), expected, page);
    assert.ok(html.includes('<meta name="viewport" content="width=device-width, initial-scale=1">'), page);
    assert.ok(html.includes('<html lang="bn">'), page);
  }
});

Deno.test("no outside scripts or resources; the static pages have no script at all", () => {
  for (const page of PAGES) {
    const html = read(page);
    assert.ok(!/(src|href)="(https?:)?\/\//i.test(html), `${page}: outside resource`);
    for (const m of html.matchAll(/<script\b[^>]*>/gi)) {
      assert.match(m[0], /src="[a-z_]+\.js"/, `${page}: inline or outside script`);
    }
  }
  for (const page of STATIC) assert.ok(!/<script\b/i.test(read(page)), `${page}: has a script`);
});

Deno.test("no innerHTML / outerHTML / insertAdjacentHTML / document.write anywhere in the pay page", () => {
  const files = [...Deno.readDirSync(dir)].filter((e) => e.isFile && /\.(js|html)$/.test(e.name)).map((e) => e.name);
  assert.ok(files.length >= 8);
  for (const f of files) {
    assert.ok(!/innerHTML|outerHTML|insertAdjacentHTML|document\.write/.test(read(f)), f);
  }
});

Deno.test("footer links: the pay page links privacy and terms; the site pages link all three", () => {
  const index = read("index.html");
  assert.ok(index.includes('<footer class="site-foot">'));
  assert.ok(index.includes('href="privacy.html">গোপনীয়তা নীতি</a>'));
  assert.ok(index.includes('href="terms.html">শর্তাবলি</a>'));
  for (const page of STATIC) {
    const html = read(page);
    for (const link of ["privacy.html", "terms.html", "download.html"]) assert.ok(html.includes(`href="${link}"`), `${page} -> ${link}`);
  }
});

Deno.test("privacy and terms: the lawyer notice comes first; placeholders are clearly marked", () => {
  for (const page of ["privacy.html", "terms.html"]) {
    const html = read(page);
    const notice = html.indexOf("আইনজীবীর পর্যালোচনা প্রয়োজন");
    assert.ok(notice > 0 && notice < html.indexOf("<h1>"), page);
    assert.ok(html.includes("REPLACE_ME_SUPPORT_CONTACT"), page);
  }
});

Deno.test("download: version, size, SHA-256, the Bangla install steps and the download-only-here warning", () => {
  const html = read("download.html");
  for (const text of ["REPLACE_ME_VERSION", "REPLACE_ME_SIZE", "REPLACE_ME_SHA256", "SHA-256"]) {
    assert.ok(html.includes(text), text);
  }
  assert.ok(html.includes("অজানা উৎস থেকে ইনস্টল চালু করুন"));
  assert.ok(html.includes("শুধু এই পেজ থেকেই BDPay ডাউনলোড করুন"));
  assert.ok(/class="hash"/.test(html), "the SHA-256 can wrap");
});

Deno.test("320 px: no fixed or minimum width over 320 px; long text wraps", () => {
  const css = read("styles.css");
  for (const m of css.matchAll(/(?<![-\w])(min-width|width)\s*:\s*(\d+)px/g)) {
    assert.ok(Number(m[2]) <= 320, `${m[1]}: ${m[2]}px`);
  }
  assert.ok(/body\s*{[^}]*overflow-x:\s*hidden/.test(css));
  for (const cls of [".hash", ".legal p, .legal li", ".notice-red", ".button-link"]) {
    const rule = new RegExp(`${cls.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*{[^}]*overflow-wrap:\\s*anywhere`);
    assert.ok(rule.test(css), cls);
  }
});
