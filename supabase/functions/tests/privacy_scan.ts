// Spec 11 privacy scan for generated emails (plan D64). Shared by alert_messages_test and, later,
// alerts_check_test (every mail in the FakeMailer outbox).

const BANGLA_DIGITS = "০১২৩৪৫৬৭৮৯";

function latinDigits(text: string): string {
  return text.replace(/[০-৯]/g, (d) => String(BANGLA_DIGITS.indexOf(d)));
}

/** What a leak looks like. Times ("01:05 AM") and dates ("01 Nov") are not phone numbers. */
const PATTERNS: { name: string; re: RegExp }[] = [
  // Bangladeshi mobile number: 01[3-9] + 8 digits, with an optional +88 / 88 prefix.
  { name: "phone", re: /(?<!\d)(?:\+?88)?01[3-9]\d{8}(?!\d)/ },
  // TrxID-like: 8-14 upper-case letters/digits with at least one digit, or 8-14 digits.
  {
    name: "trxId",
    re: /(?<![A-Z0-9])(?=[A-Z0-9]*\d)[A-Z0-9]{8,14}(?![A-Z0-9])/,
  },
  // A taka amount.
  { name: "amount", re: /৳\s*\d/ },
  // An email address.
  { name: "email", re: /@/ },
];

/** The names of the patterns found in the subject or text; empty when the email is clean. */
export function privacyLeaks(
  mail: { subject: string; text: string },
): string[] {
  const all = latinDigits(`${mail.subject}\n${mail.text}`);
  return PATTERNS.filter((p) => p.re.test(all)).map((p) => p.name);
}
