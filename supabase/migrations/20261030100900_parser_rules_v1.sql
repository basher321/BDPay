-- BDPay: the SMS parser rules version 1 (supabase/functions/_shared/parser_rules.json, the same file the app
-- bundles). Configuration the server needs to accept any SMS - not sample data. Later versions are loaded with
-- supabase/scripts/load_parser_rules.ts or a new migration; this one only inserts when no version 1 exists.
insert into public.parser_rules (version, rules, is_active)
select 1, $rules$[
  {
    "note": "SAMPLE - verify with real SMS. Patterns have no inline flags; Kotlin and Dart compile them case-insensitive. Before matching, Bangla digits become English digits and Unicode spaces become a normal space. Do not use '.' as a wildcard or \\b. payer: the first group that matched.",
    "version": 1,
    "operator": "bkash",
    "senders": ["bKash", "16247"],
    "incoming": "you have received|পেয়েছেন",
    "ignore": "(?<![a-z])(?:otp|pin|offer|cashback)(?![a-z])|verification code|কোড|অফার|ক্যাশব্যাক|ওটিপি|পিন",
    "trx": "TrxID\\s*:?\\s*([A-Z0-9]{8,12})",
    "amount": "(?:Tk|৳|BDT)\\s?([0-9,]+(?:\\.[0-9]{1,2})?)",
    "payer": "(?:from|Sender:?)\\s*(01[0-9]{9,10})|(01[0-9]{9,10})\\s*থেকে",
    "balance": "Balance:?\\s*Tk\\s?([0-9,]+(?:\\.[0-9]{1,2})?)",
    "reference": "(?<![a-z])Ref(?:erence)?(?![a-z]):?\\s*([A-Za-z0-9#-]+)",
    "payment": "payment"
  },
  {
    "note": "SAMPLE - verify with real SMS. Patterns have no inline flags; Kotlin and Dart compile them case-insensitive. Before matching, Bangla digits become English digits and Unicode spaces become a normal space. Do not use '.' as a wildcard or \\b. payer: the first group that matched.",
    "version": 1,
    "operator": "nagad",
    "senders": ["NAGAD", "16167"],
    "incoming": "money received",
    "ignore": "(?<![a-z])(?:otp|pin|offer|cashback)(?![a-z])|verification code|কোড|অফার|ক্যাশব্যাক|ওটিপি|পিন",
    "trx": "TxnID\\s*:?\\s*([A-Z0-9]{8,12})",
    "amount": "(?:Tk|৳|BDT)\\s?([0-9,]+(?:\\.[0-9]{1,2})?)",
    "payer": "(?:from|Sender:?)\\s*(01[0-9]{9,10})|(01[0-9]{9,10})\\s*থেকে",
    "balance": "Balance:?\\s*Tk\\s?([0-9,]+(?:\\.[0-9]{1,2})?)",
    "reference": "(?<![a-z])Ref(?:erence)?(?![a-z]):?\\s*([A-Za-z0-9#-]+)",
    "payment": "payment"
  },
  {
    "note": "SAMPLE - verify with real SMS. Patterns have no inline flags; Kotlin and Dart compile them case-insensitive. Before matching, Bangla digits become English digits and Unicode spaces become a normal space. Do not use '.' as a wildcard or \\b. payer: the first group that matched.",
    "version": 1,
    "operator": "rocket",
    "senders": ["16216"],
    "incoming": "received from",
    "ignore": "(?<![a-z])(?:otp|pin|offer|cashback)(?![a-z])|verification code|কোড|অফার|ক্যাশব্যাক|ওটিপি|পিন",
    "trx": "TxnId\\s*:?\\s*([0-9]{8,14})",
    "amount": "(?:Tk|৳|BDT)\\s?([0-9,]+(?:\\.[0-9]{1,2})?)",
    "payer": "(?:from|Sender:?)\\s*(01[0-9]{9,10})|(01[0-9]{9,10})\\s*থেকে",
    "balance": "Balance:?\\s*Tk\\s?([0-9,]+(?:\\.[0-9]{1,2})?)",
    "reference": "(?<![a-z])Ref(?:erence)?(?![a-z]):?\\s*([A-Za-z0-9#-]+)",
    "payment": "payment"
  },
  {
    "note": "SAMPLE - verify with real SMS. Patterns have no inline flags; Kotlin and Dart compile them case-insensitive. Before matching, Bangla digits become English digits and Unicode spaces become a normal space. Do not use '.' as a wildcard or \\b. payer: the first group that matched.",
    "version": 1,
    "operator": "upay",
    "senders": ["upay", "16268"],
    "incoming": "you have received",
    "ignore": "(?<![a-z])(?:otp|pin|offer|cashback)(?![a-z])|verification code|কোড|অফার|ক্যাশব্যাক|ওটিপি|পিন",
    "trx": "Txn ID\\s*:?\\s*([A-Z0-9]{8,12})",
    "amount": "(?:Tk|৳|BDT)\\s?([0-9,]+(?:\\.[0-9]{1,2})?)",
    "payer": "(?:from|Sender:?)\\s*(01[0-9]{9,10})|(01[0-9]{9,10})\\s*থেকে",
    "balance": "Balance:?\\s*Tk\\s?([0-9,]+(?:\\.[0-9]{1,2})?)",
    "reference": "(?<![a-z])Ref(?:erence)?(?![a-z]):?\\s*([A-Za-z0-9#-]+)",
    "payment": "payment"
  }
]$rules$::jsonb, not exists (select 1 from public.parser_rules where is_active)
where not exists (select 1 from public.parser_rules where version = 1);
