// Screens and events of the pay page (spec 07).
// Safety: every node is built with createElement and every text goes in with textContent. Attributes get only
// fixed values from this file. Server values for operator and account type are checked against known values.
// The page shows "verified" only when the server's status says so.
import * as api from "./api.js";
import { operatorName, stepsFor } from "./instructions.js";
import {
  formatCountdown,
  formatDhakaTime,
  formatPoisha,
  isSafeReturnUrl,
  isValidTrxId,
  nextPollDelay,
  normalizeTrxId,
} from "./logic.js";

// All page text in one place.
const STRINGS = {
  loading: "লোড হচ্ছে…",
  notFoundTitle: "এই পেমেন্ট লিংক পাওয়া যায়নি",
  notFoundHint: "দোকান থেকে পাওয়া লিংকটি আবার খুলুন",
  order: (ref) => `অর্ডার ${ref}`,
  timeLeft: (cd) => `সময় বাকি ${cd}`,
  exactAmount: (amount) => `ঠিক ${amount} পাঠান — কম বা বেশি পাঠালে যাচাই হবে না।`,
  copy: "⧉ কপি",
  copied: "কপি হয়েছে",
  copyBlocked: "কপি করা যায়নি — নম্বরটি দেখে লিখে নিন",
  trxLabel: "পেমেন্টের পর পাওয়া TrxID দিন",
  verify: "যাচাই করুন",
  sending: "পাঠানো হচ্ছে…",
  attemptsLeft: (n) => `${n} বার চেষ্টা বাকি`,
  footer: "BDPay দিয়ে নিরাপদ যাচাই • আপনার পিন কখনো চাওয়া হবে না",
  invalidTrx: "TrxID সঠিক নয় — এসএমএস থেকে আবার দেখুন",
  alreadyUsed: "এই TrxID আগেই ব্যবহার হয়েছে",
  noAttemptsLeft: "আর চেষ্টা করা যাবে না — দোকানে যোগাযোগ করুন",
  rateLimited: "অনেকবার চেষ্টা হয়েছে — একটু পরে আবার চেষ্টা করুন",
  network: "ইন্টারনেট সংযোগ দেখুন",
  pendingTitle: "পেমেন্ট যাচাই হচ্ছে…",
  pendingSoon: "সাধারণত ১ মিনিটের মধ্যে নিশ্চিত হয়",
  pendingLate: "এখনো নিশ্চিত হয়নি — এই পেজ খোলা রাখুন বা পরে এই লিংকে ফিরে আসুন",
  deviceOffline: "দোকানের যাচাই ফোন এখন অফলাইন — নিশ্চিত হতে দেরি হতে পারে",
  changeTrx: "TrxID ভুল দিয়েছেন? বদলান",
  opAndTrx: (op, trx) => `${op} • TrxID ${trx}`,
  verifiedTitle: "পেমেন্ট নিশ্চিত হয়েছে",
  backToShop: "দোকানে ফিরে যান",
  mismatchTitle: "টাকার পরিমাণ মেলেনি",
  mismatchText: (trx) => `দোকান আপনার পেমেন্ট দেখে নিশ্চিত করবে। প্রয়োজনে দোকানে এই TrxID জানান: ${trx}`,
  expiredTitle: "সময় শেষ",
  expiredText: "এই অর্ডারের পেমেন্টের সময় পার হয়ে গেছে।",
  expiredHint: "টাকা পাঠিয়ে থাকলে TrxID সহ দোকানে যোগাযোগ করুন।",
  rejectedTitle: "পেমেন্ট গ্রহণ করা হয়নি",
  rejectedText: (trx) => `দোকান এই পেমেন্টটি গ্রহণ করেনি। TrxID ${trx} সহ দোকানে যোগাযোগ করুন।`,
};

const TWO_MINUTES = 120000;
const SOON_MS = 5 * 60 * 1000;
const MISMATCH_POLL_MS = 10000;
const ACCOUNT_TYPES = ["merchant", "agent"];

const root = document.getElementById("app");
const toastBox = document.getElementById("toast");

const state = {
  token: new URLSearchParams(location.search).get("t") ?? "",
  session: null,
  screen: "loading",
  selectedOp: null,
  prefillTrx: "",
  submitAt: null,
  busy: false,
  pollTimer: null,
  countdownTimer: null,
  toastTimer: null,
};

// ---------- small DOM helpers (text only) ----------

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined && text !== null) node.textContent = String(text);
  return node;
}

function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
}

function show(...children) {
  clear(root);
  for (const c of children) if (c) root.appendChild(c);
}

function toast(message) {
  toastBox.textContent = message;
  toastBox.hidden = false;
  clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => {
    toastBox.hidden = true;
  }, 1800);
}

function backButton(session) {
  if (!isSafeReturnUrl(session.returnUrl)) return null;
  const b = el("button", "btn", STRINGS.backToShop);
  b.type = "button";
  b.addEventListener("click", () => location.assign(session.returnUrl));
  return b;
}

/** Only wallets with a known operator and account type are shown. */
function knownOperators(session) {
  return (Array.isArray(session.operators) ? session.operators : []).filter(
    (o) => o && operatorName(o.operator) !== null && ACCOUNT_TYPES.includes(o.accountType),
  );
}

function amountText(session) {
  try {
    return formatPoisha(session.amountPoisha);
  } catch {
    return "";
  }
}

function msLeft(session) {
  return Date.parse(session.expiresAt) - Date.now();
}

// ---------- timers ----------

function stopTimers() {
  clearTimeout(state.pollTimer);
  clearInterval(state.countdownTimer);
  state.pollTimer = null;
  state.countdownTimer = null;
}

/** Updates [node] every second; at 0 checks the status once more, then routes. */
function startCountdown(node, onTick) {
  const tick = () => {
    const left = msLeft(state.session);
    node.textContent = STRINGS.timeLeft(formatCountdown(left));
    node.classList.toggle("soon", left < SOON_MS);
    if (onTick) onTick();
    if (left <= 0) {
      clearInterval(state.countdownTimer);
      state.countdownTimer = null;
      finalCheck();
    }
  };
  tick();
  state.countdownTimer = setInterval(tick, 1000);
}

async function finalCheck() {
  clearTimeout(state.pollTimer);
  try {
    const s = await api.getStatus(state.token);
    if (s.error) return renderNotFound();
    state.session = s;
    if (s.status === "verified" || s.status === "mismatch" || s.status === "rejected") return route();
  } catch {
    // Network trouble: still show the expired screen; reopening the link shows the real status.
  }
  state.session = { ...state.session, status: "expired" };
  route();
}

function schedulePoll() {
  clearTimeout(state.pollTimer);
  if (document.hidden) return; // paused; resumed by visibilitychange
  const s = state.session;
  let delay;
  if (s.status === "pending") delay = nextPollDelay(Date.now() - (state.submitAt ?? Date.now()));
  else if (s.status === "mismatch") delay = MISMATCH_POLL_MS;
  else return; // verified / expired / open: no polling
  state.pollTimer = setTimeout(poll, delay);
}

async function poll() {
  state.pollTimer = null;
  try {
    const s = await api.getStatus(state.token);
    if (s.error) return renderNotFound();
    const changed = s.status !== state.session.status;
    state.session = s;
    if (changed) return route();
    if (s.status === "pending") updatePendingNotes();
  } catch {
    // Keep polling; the next try may work.
  }
  schedulePoll();
}

document.addEventListener("visibilitychange", () => {
  if (document.hidden) {
    clearTimeout(state.pollTimer);
    state.pollTimer = null;
  } else if (state.screen === "pending" || state.screen === "mismatch") {
    poll();
  }
});

// ---------- screens ----------

function route() {
  stopTimers();
  const s = state.session;
  switch (s.status) {
    case "open":
      return renderOpen();
    case "pending":
      if (state.submitAt === null) state.submitAt = Date.now();
      return renderPending();
    case "verified":
      return renderVerified();
    case "mismatch":
      return renderMismatch();
    case "expired":
      return renderExpired();
    case "rejected":
      return renderRejected();
    default:
      return renderNotFound();
  }
}

function renderLoading(message) {
  state.screen = "loading";
  const card = el("div", "card big surface center");
  if (!message) card.appendChild(el("div", "spinner"));
  card.appendChild(el("p", message ? "error" : "muted", message ?? STRINGS.loading));
  show(card);
}

function renderNotFound() {
  stopTimers();
  state.screen = "notFound";
  const card = el("div", "card big surface center");
  card.appendChild(el("p", "title", STRINGS.notFoundTitle));
  card.appendChild(el("p", "muted", STRINGS.notFoundHint));
  show(card);
}

function merchantCard(session) {
  const card = el("div", "card big surface center");
  card.appendChild(el("div", "merchant", session.merchantName));
  card.appendChild(el("div", "muted", STRINGS.order(session.orderRef)));
  card.appendChild(el("div", "amount", amountText(session)));
  const cd = el("div", "countdown");
  card.appendChild(cd);
  return { card, countdown: cd };
}

function renderOpen() {
  state.screen = "open";
  const s = state.session;
  const ops = knownOperators(s);
  if (!ops.some((o) => o.operator === state.selectedOp)) state.selectedOp = ops[0]?.operator ?? null;

  const { card, countdown } = merchantCard(s);
  const warn = el("p", "warn", STRINGS.exactAmount(amountText(s)));

  // c. Operator tabs (none when there is only one operator).
  let tabs = null;
  if (ops.length > 1) {
    tabs = el("div", "tabs");
    tabs.setAttribute("role", "tablist");
    for (const o of ops) {
      const t = el("button", `tab op-${o.operator}`, operatorName(o.operator));
      t.type = "button";
      t.setAttribute("role", "tab");
      const selected = o.operator === state.selectedOp;
      t.setAttribute("aria-selected", selected ? "true" : "false");
      if (selected) t.classList.add("selected");
      t.addEventListener("click", () => {
        state.prefillTrx = input.value;
        state.selectedOp = o.operator;
        renderOpen();
      });
      tabs.appendChild(t);
    }
  }

  // d. Steps card.
  const steps = el("div", "card");
  const current = ops.find((o) => o.operator === state.selectedOp);
  if (current) {
    steps.appendChild(el("div", `op-name op-${current.operator}`, operatorName(current.operator)));
    const row = el("div", "wallet-row");
    row.appendChild(el("span", "wallet", current.walletNumber));
    const copy = el("button", "btn small", STRINGS.copy);
    copy.type = "button";
    copy.addEventListener("click", () => copyWallet(String(current.walletNumber ?? "")));
    row.appendChild(copy);
    steps.appendChild(row);
    const info = stepsFor(current.operator, current.accountType, current.walletNumber, amountText(s), s.orderRef);
    if (info) {
      const list = el("ol", "steps");
      for (const line of info.steps) list.appendChild(el("li", null, line));
      steps.appendChild(list);
      if (info.extra) steps.appendChild(el("p", "steps-extra", info.extra));
    }
  }

  // e. TrxID form.
  const form = el("form", "card");
  form.noValidate = true;
  const label = el("label", "field", STRINGS.trxLabel);
  label.htmlFor = "trx";
  const input = el("input", "trx");
  input.id = "trx";
  input.type = "text";
  input.autocomplete = "off";
  input.setAttribute("autocapitalize", "characters");
  input.setAttribute("autocorrect", "off");
  input.spellcheck = false;
  input.inputMode = "text";
  input.maxLength = 40;
  input.value = state.prefillTrx;
  const error = el("p", "error");
  error.hidden = true;
  const button = el("button", "btn", STRINGS.verify);
  button.type = "submit";
  const attempts = el("p", "attempts", STRINGS.attemptsLeft(s.attemptsLeft));
  form.append(label, input, error, button, attempts);
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    submit(input, button, error, attempts);
  });

  const footer = el("p", "footer", STRINGS.footer);
  show(card, warn, tabs, current ? steps : null, form, footer);
  startCountdown(countdown);
}

async function copyWallet(wallet) {
  try {
    if (!navigator.clipboard || !globalThis.isSecureContext) throw new Error("blocked");
    await navigator.clipboard.writeText(wallet);
    toast(STRINGS.copied);
  } catch {
    toast(STRINGS.copyBlocked);
  }
}

async function submit(input, button, error, attempts) {
  if (state.busy) return; // a second tap while sending does nothing
  const operator = state.selectedOp;
  const trx = normalizeTrxId(input.value);
  input.value = trx;
  const fail = (message) => {
    error.textContent = message;
    error.hidden = false;
  };
  if (!operator || !isValidTrxId(operator, trx)) return fail(STRINGS.invalidTrx);

  state.busy = true;
  error.hidden = true;
  button.disabled = true;
  button.textContent = STRINGS.sending;
  let res;
  try {
    res = await api.submitClaim(state.token, operator, trx);
  } catch {
    res = null;
  } finally {
    state.busy = false;
    button.disabled = false;
    button.textContent = STRINGS.verify;
  }
  if (res === null) return fail(STRINGS.network); // the form stays filled

  if (res.session) state.session = res.session;
  attempts.textContent = STRINGS.attemptsLeft(state.session.attemptsLeft);
  switch (res.result) {
    case "accepted":
      state.prefillTrx = "";
      state.submitAt = Date.now();
      return route();
    case "invalidFormat":
      return fail(STRINGS.invalidTrx);
    case "alreadyUsed":
      return fail(STRINGS.alreadyUsed);
    case "noAttemptsLeft":
      return fail(STRINGS.noAttemptsLeft);
    case "rateLimited":
      return fail(STRINGS.rateLimited);
    case "expired":
      state.session = { ...state.session, status: "expired" };
      return route();
    case "notFound":
      return renderNotFound();
    default:
      return fail(STRINGS.network);
  }
}

let pendingNotes = null;

function updatePendingNotes() {
  if (!pendingNotes) return;
  const late = Date.now() - (state.submitAt ?? Date.now()) >= TWO_MINUTES;
  pendingNotes.wait.textContent = late ? STRINGS.pendingLate : STRINGS.pendingSoon;
  pendingNotes.offline.hidden = state.session.deviceOnline !== false;
  pendingNotes.change.hidden = !(state.session.attemptsLeft > 0);
}

function renderPending() {
  state.screen = "pending";
  const s = state.session;
  const card = el("div", "card big surface center");
  card.appendChild(el("div", "spinner"));
  card.appendChild(el("p", "title", STRINGS.pendingTitle));
  const opName = operatorName(s.submittedOperator) ?? "";
  card.appendChild(el("p", "muted", STRINGS.opAndTrx(opName, s.submittedTrxId ?? "")));
  card.appendChild(el("div", "amount", amountText(s)));
  const cd = el("div", "countdown");
  card.appendChild(cd);
  const wait = el("p", "muted");
  card.appendChild(wait);

  const offline = el("p", "note-amber", STRINGS.deviceOffline);
  const change = el("button", "link", STRINGS.changeTrx);
  change.type = "button";
  change.addEventListener("click", () => {
    stopTimers();
    state.selectedOp = s.submittedOperator;
    state.prefillTrx = s.submittedTrxId ?? "";
    renderOpen();
  });
  const changeRow = el("div", "center");
  changeRow.appendChild(change);
  pendingNotes = { wait, offline, change: changeRow };
  updatePendingNotes();

  show(card, offline, changeRow, el("p", "footer", STRINGS.footer));
  startCountdown(cd, updatePendingNotes);
  schedulePoll();
}

function renderVerified() {
  state.screen = "verified";
  const s = state.session;
  const card = el("div", "card big surface center");
  card.appendChild(el("div", "big-mark ok", "✓"));
  card.appendChild(el("p", "title", STRINGS.verifiedTitle));
  card.appendChild(el("div", "amount", amountText(s)));
  card.appendChild(el("p", "muted", STRINGS.opAndTrx(operatorName(s.submittedOperator) ?? "", s.submittedTrxId ?? "")));
  card.appendChild(el("p", "muted", STRINGS.order(s.orderRef)));
  card.appendChild(el("p", "muted", formatDhakaTime(s.verifiedAt)));
  show(card, backButton(s));
}

function renderMismatch() {
  state.screen = "mismatch";
  const s = state.session;
  const card = el("div", "card big surface center");
  card.appendChild(el("div", "big-mark warn", "!"));
  card.appendChild(el("p", "title", STRINGS.mismatchTitle));
  card.appendChild(el("p", "muted", STRINGS.mismatchText(s.submittedTrxId ?? "")));
  show(card, backButton(s));
  schedulePoll(); // every 10 s: the merchant may approve it by hand (spec 03)
}

function renderExpired() {
  state.screen = "expired";
  const s = state.session;
  const card = el("div", "card big surface center");
  card.appendChild(el("p", "title", STRINGS.expiredTitle));
  card.appendChild(el("p", "muted", STRINGS.expiredText));
  card.appendChild(el("p", "muted", STRINGS.expiredHint));
  show(card, backButton(s));
}

/** Spec 07a: the merchant rejected the payment. No countdown, no polling. */
function renderRejected() {
  state.screen = "rejected";
  const s = state.session;
  const card = el("div", "card big surface center");
  card.appendChild(el("div", "big-mark er", "✕"));
  card.appendChild(el("p", "title", STRINGS.rejectedTitle));
  card.appendChild(el("p", "muted", STRINGS.rejectedText(s.submittedTrxId ?? "")));
  show(card, backButton(s));
}

// ---------- start ----------

async function start() {
  renderLoading();
  if (!state.token) return renderNotFound();
  try {
    const s = await api.getSession(state.token);
    if (!s || s.error) return renderNotFound();
    state.session = s;
    route();
  } catch {
    renderLoading(STRINGS.network);
  }
}

start();
