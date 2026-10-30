import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../enums.dart';

/// One operator's rules from android/app/src/main/res/raw/parser_rules.json (the only copy;
/// the app gets it through the channel). Patterns compile case-insensitive, like in Kotlin.
@immutable
class ParserRule {
  const ParserRule({
    required this.operator,
    required this.senders,
    required this.incoming,
    required this.ignore,
    required this.trx,
    required this.amount,
    required this.payer,
    required this.balance,
    required this.reference,
    required this.payment,
    required this.version,
  });

  final MfsOperator operator;
  final List<String> senders;
  final RegExp incoming;
  final RegExp ignore;
  final RegExp trx;
  final RegExp amount;
  final RegExp payer;
  final RegExp balance;
  final RegExp reference;
  final RegExp payment;
  final int version;

  factory ParserRule.fromJson(Map<String, dynamic> j) {
    RegExp re(String key) => RegExp(j[key] as String, caseSensitive: false);
    return ParserRule(
      operator: MfsOperator.fromWire(j['operator'] as String),
      senders: [for (final s in j['senders'] as List) s as String],
      incoming: re('incoming'),
      ignore: re('ignore'),
      trx: re('trx'),
      amount: re('amount'),
      payer: re('payer'),
      balance: re('balance'),
      reference: re('reference'),
      payment: re('payment'),
      version: j['version'] as int,
    );
  }
}

/// Parses the rules file (a JSON array, one object per operator).
List<ParserRule> parseRules(String json) =>
    [for (final o in jsonDecode(json) as List) ParserRule.fromJson(o as Map<String, dynamic>)];

/// Sender compare form: trimmed, lower case.
String normalizeSender(String sender) => sender.trim().toLowerCase();

/// The rule whose senders contain [sender], or null.
ParserRule? ruleForSender(List<ParserRule> rules, String sender) {
  final s = normalizeSender(sender);
  for (final r in rules) {
    if (r.senders.any((x) => normalizeSender(x) == s)) return r;
  }
  return null;
}
