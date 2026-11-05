import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/parser/parse_sms.dart';
import 'package:verifier/domain/parser/parser_rule.dart';

/// The one rules file (no copy), read from disk.
List<ParserRule> loadRules() =>
    parseRules(File('android/app/src/main/res/raw/parser_rules.json').readAsStringSync());

void main() {
  final rules = loadRules();

  test('the rules file has the 4 operators', () {
    expect(rules.map((r) => r.operator), MfsOperator.values);
  });

  test('bKash reference sample', () {
    final p = parseSms(
      'bKash',
      'You have received payment Tk 1,250.00 from 01712345678. Ref: ORD-101. Fee Tk 0.00. '
          'Balance Tk 15,340.50. TrxID 9K48X7Z2 at 02/10/2026 18:25',
      rules,
    );
    expect(p.ok, isTrue);
    expect(p.operator, MfsOperator.bkash);
    expect(p.trxId, '9K48X7Z2');
    expect(p.amountPoisha, 125000);
    expect(p.payerNumber, '01712345678');
    expect(p.balancePoisha, 1534050);
    expect(p.reference, 'ORD-101');
    expect(p.kind, TxKind.payment);
  });

  test('Nagad reference sample', () {
    final p = parseSms(
      'NAGAD',
      'Money Received Amount: Tk 2,500.00 Sender: 01812345678 TxnID: 71B99AA2 Balance: Tk 15,000.00 '
          'Time: 02/10/2026 14:15',
      rules,
    );
    expect(p.ok, isTrue);
    expect(p.operator, MfsOperator.nagad);
    expect(p.trxId, '71B99AA2');
    expect(p.amountPoisha, 250000);
    expect(p.payerNumber, '01812345678');
    expect(p.kind, TxKind.received);
  });

  test('Rocket reference sample', () {
    final p = parseSms(
      '16216',
      'Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. '
          'TxnId: 24010200123',
      rules,
    );
    expect(p.ok, isTrue);
    expect(p.operator, MfsOperator.rocket);
    expect(p.trxId, '24010200123');
    expect(p.amountPoisha, 150000);
    expect(p.payerNumber, '017123456789');
    expect(p.balancePoisha, 560000);
  });

  test('Upay reference sample', () {
    final p = parseSms(
      'upay',
      'You have received Tk 800.00 from 01711223344. Txn ID: 4UP82910. Current balance Tk 3,400.00. Fee Tk 0.00.',
      rules,
    );
    expect(p.ok, isTrue);
    expect(p.operator, MfsOperator.upay);
    expect(p.trxId, '4UP82910');
    expect(p.amountPoisha, 80000);
    expect(p.payerNumber, '01711223344');
  });

  test('Bangla bKash sample: amount 125000 and payer from the "থেকে" form', () {
    final p = parseSms(
      'bKash',
      'আপনি 01712345678 থেকে Tk 1,250.00 পেয়েছেন। Ref: ORDER-99। ব্যালেন্স Tk 15,340.50। TrxID 9K48X7B5',
      rules,
    );
    expect(p.ok, isTrue);
    expect(p.amountPoisha, 125000);
    expect(p.payerNumber, '01712345678');
    expect(p.trxId, '9K48X7B5');
    expect(p.reference, 'ORDER-99');
  });

  test('Bangla digits "৳ ১,২৫০.০০" -> 125000', () {
    final p = parseSms('bKash', 'আপনি ০১৭১২৩৪৫৬৭৮ থেকে ৳ ১,২৫০.০০ পেয়েছেন। TrxID 9K48X7B5', rules);
    expect(p.amountPoisha, 125000);
    expect(p.payerNumber, '01712345678');
  });

  test('no TrxID -> ok false with an error', () {
    final p = parseSms('bKash', 'You have received Tk 100.00 from 01712345678.', rules);
    expect(p.ok, isFalse);
    expect(p.errors, [ParseError.noTrxId]);
  });

  test('no amount -> ok false; unknown sender -> ok false', () {
    expect(parseSms('bKash', 'You have received money. TrxID ABC12345', rules).errors, [ParseError.noAmount]);
    expect(parseSms('01799999999', 'TrxID ABC12345 Tk 5', rules).errors, [ParseError.unknownSender]);
  });

  test('sender " BKASH " matches; TrxID is upper case', () {
    final p = parseSms(' BKASH ', 'You have received Tk 5.00 from 01712345678. TrxID abc12345', rules);
    expect(p.operator, MfsOperator.bkash);
    expect(p.trxId, 'ABC12345');
  });

  test('"Refund" is not a reference (D15)', () {
    final p = parseSms('bKash', 'You have received Tk 5.00 Refund from 01712345678. TrxID ABC12345', rules);
    expect(p.reference, isNull);
  });

  test('HTML in the body is kept as plain text, not interpreted', () {
    final p = parseSms(
      'bKash',
      'You have received Tk 100.00 from 01712345678. <img src=x onerror=alert(1)> TrxID HTML1234',
      rules,
    );
    expect(p.ok, isTrue);
    expect(p.trxId, 'HTML1234');
  });
}
