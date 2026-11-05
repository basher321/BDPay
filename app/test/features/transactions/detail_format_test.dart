import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/features/transactions/detail/detail_format.dart';

void main() {
  test('difference: expected 45000, SMS 43000 -> "৳ 20.00 কম"', () {
    expect(amountDifference(45000, 43000), '৳ 20.00 কম');
  });

  test('difference: SMS higher -> বেশি; equal -> no word', () {
    expect(amountDifference(43000, 45000), '৳ 20.00 বেশি');
    expect(amountDifference(45000, 45000), '৳ 0.00');
  });

  test('full date and time in Dhaka', () {
    expect(dhakaDateTime(DateTime.utc(2026, 10, 29, 12, 25)), '29 Oct 2026, 06:25 PM');
  });
}
