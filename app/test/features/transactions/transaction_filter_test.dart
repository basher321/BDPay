import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/features/transactions/transaction_filter.dart';

void main() {
  final all = buildSampleTransactions(DateTime.utc(2026, 10, 29, 6));

  test('query "9k48" finds 1', () {
    expect(filterTransactions(all, query: '9k48').map((t) => t.trxId), ['9K48X7Z2']);
  });

  test('query "  0181  " finds 1', () {
    expect(filterTransactions(all, query: '  0181  ').map((t) => t.id), ['2']);
  });

  test('operator bkash finds 2', () {
    expect(filterTransactions(all, operator: MfsOperator.bkash).length, 2);
  });

  test('statuses {mismatch, rejected} finds 1', () {
    expect(filterTransactions(all, statuses: {VerifyStatus.mismatch, VerifyStatus.rejected}).length, 1);
  });

  test('operator rocket + statuses {verified} finds 0', () {
    expect(filterTransactions(all, operator: MfsOperator.rocket, statuses: {VerifyStatus.verified}), isEmpty);
  });

  test('spaces-only and empty search find everything', () {
    expect(filterTransactions(all, query: '   ').length, 5);
    expect(filterTransactions(all).length, 5);
  });
}
