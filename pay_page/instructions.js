// Payment steps per operator and account type (spec 07). Plain text only; the page puts them in with textContent.

const NOTE = "SAMPLE - check the wording in each operator's app";

const NAMES = { bkash: "bKash", nagad: "Nagad", rocket: "Rocket", upay: "Upay" };

const merchant = (name) => ({
  note: NOTE,
  steps: (wallet, amount, orderRef) => [
    `${name} অ্যাপ খুলে "Make Payment" (পেমেন্ট) চাপুন`,
    `মার্চেন্ট নম্বর দিন: ${wallet}`,
    `টাকার পরিমাণ দিন: ${amount}`,
    `রেফারেন্স: ${orderRef}`,
    `${name} অ্যাপে আপনার পিন দিয়ে নিশ্চিত করুন — পিন শুধু ${name} অ্যাপে দেবেন, এই পেজে নয়`,
  ],
});

const agent = (name, app) => ({
  note: NOTE,
  steps: (wallet, amount, orderRef) => [
    `${app} খুলে "Cash Out" (ক্যাশ আউট) চাপুন`,
    `এজেন্ট নম্বর দিন: ${wallet}`,
    `টাকার পরিমাণ দিন: ${amount}`,
    `রেফারেন্স: ${orderRef}`,
    `${name} অ্যাপে আপনার পিন দিয়ে নিশ্চিত করুন — পিন শুধু ${name} অ্যাপে দেবেন, এই পেজে নয়`,
  ],
  // Decision D23: the sender pays the cash-out charge.
  extra: "ক্যাশ আউট চার্জ আপনার অ্যাকাউন্ট থেকে কাটা হবে",
});

const STEPS = {
  "bkash:merchant": merchant(NAMES.bkash),
  "bkash:agent": agent(NAMES.bkash, "bKash অ্যাপ"),
  "nagad:merchant": merchant(NAMES.nagad),
  "nagad:agent": agent(NAMES.nagad, "Nagad অ্যাপ"),
  "rocket:merchant": merchant(NAMES.rocket),
  "rocket:agent": agent(NAMES.rocket, "Rocket অ্যাপ (বা *322#)"),
  "upay:merchant": merchant(NAMES.upay),
  "upay:agent": agent(NAMES.upay, "Upay অ্যাপ"),
};

/** The operator's display name, or null for an unknown operator. */
export function operatorName(operator) {
  return Object.hasOwn(NAMES, operator) ? NAMES[operator] : null;
}

/**
 * {steps: string[], extra: string|null} for a known operator and account type, else null.
 * [amountText] is already formatted ("৳ 1,250.00").
 */
export function stepsFor(operator, accountType, wallet, amountText, orderRef) {
  const key = `${operator}:${accountType}`;
  if (!Object.hasOwn(STEPS, key)) return null;
  const entry = STEPS[key];
  return { steps: entry.steps(wallet, amountText, orderRef), extra: entry.extra ?? null };
}
