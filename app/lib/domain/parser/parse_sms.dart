import 'package:flutter/foundation.dart';

import '../enums.dart';
import 'parser_rule.dart';

/// Why a parse failed. Shown in Bangla in the developer lab; never contains SMS text.
enum ParseError { unknownSender, noTrxId, noAmount }

@immutable
class ParsedSms {
  const ParsedSms({
    this.operator,
    this.trxId,
    this.amountPoisha,
    this.payerNumber,
    this.balancePoisha,
    this.reference,
    this.kind = TxKind.received,
    required this.errors,
  });

  final MfsOperator? operator;

  /// Upper case.
  final String? trxId;
  final int? amountPoisha;
  final String? payerNumber;
  final int? balancePoisha;
  final String? reference;
  final TxKind kind;
  final List<ParseError> errors;

  /// A TrxID and an amount were found.
  bool get ok => errors.isEmpty;
}

const _banglaZero = 0x09E6;

// The Unicode spaces Dart's \s knows and Java's \s does not; they become ' ' on both sides (same list as Kotlin).
const _unicodeSpaces = {
  0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, //
  0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
};

/// Bangla digits -> English digits, Unicode spaces -> ' '. Same as ParserRules.normalizeBody in Kotlin.
String normalizeSmsBody(String body) => String.fromCharCodes(body.codeUnits.map((c) {
      if (c >= _banglaZero && c <= _banglaZero + 9) return c - _banglaZero + 0x30;
      if (_unicodeSpaces.contains(c)) return 0x20;
      return c;
    }));

final _amountText = RegExp(r'^([0-9]{1,13})(?:\.([0-9]{1,2}))?$');

/// "1,250.50" -> 125050, "1,250.5" -> 125050, "1,250" -> 125000, "0.5" -> 50. Whole-number math only;
/// null when the text is not an amount. Never throws (an exception message would carry SMS text).
int? amountTextToPoisha(String text) {
  final m = _amountText.firstMatch(text.replaceAll(',', ''));
  if (m == null) return null;
  final taka = int.tryParse(m.group(1)!);
  if (taka == null) return null;
  final frac = m.group(2);
  final poisha = frac == null ? 0 : int.tryParse(frac.padRight(2, '0'))!;
  return taka * 100 + poisha;
}

String? _group1(RegExp re, String text) => re.firstMatch(text)?.group(1)?.trim();

/// The first capture group that matched (the payer pattern has two forms).
String? _firstGroup(RegExp re, String text) {
  final m = re.firstMatch(text);
  if (m == null) return null;
  for (var i = 1; i <= m.groupCount; i++) {
    final g = m.group(i);
    if (g != null && g.isNotEmpty) return g;
  }
  return null;
}

/// Pure parse of one SMS with the rules. The server parses again with its own rules.
ParsedSms parseSms(String sender, String body, List<ParserRule> rules) {
  final rule = ruleForSender(rules, sender);
  if (rule == null) return const ParsedSms(errors: [ParseError.unknownSender]);
  final text = normalizeSmsBody(body);
  final trx = _group1(rule.trx, text)?.toUpperCase();
  final amountText = _group1(rule.amount, text);
  final amount = amountText == null ? null : amountTextToPoisha(amountText);
  final balanceText = _group1(rule.balance, text);
  return ParsedSms(
    operator: rule.operator,
    trxId: trx,
    amountPoisha: amount,
    payerNumber: _firstGroup(rule.payer, text),
    balancePoisha: balanceText == null ? null : amountTextToPoisha(balanceText),
    reference: _group1(rule.reference, text),
    kind: rule.payment.hasMatch(text) ? TxKind.payment : TxKind.received,
    errors: [
      if (trx == null || trx.isEmpty) ParseError.noTrxId,
      if (amount == null) ParseError.noAmount,
    ],
  );
}
