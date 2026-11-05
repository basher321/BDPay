import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/time.dart';

void main() {
  final now = DateTime.utc(2026, 10, 29, 6);

  test('timeAgo', () {
    expect(timeAgo(now.subtract(const Duration(seconds: 30)), now), 'এইমাত্র');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), '5 মিনিট আগে');
    expect(timeAgo(now.subtract(const Duration(hours: 2)), now), '2 ঘণ্টা আগে');
    expect(timeAgo(now.subtract(const Duration(days: 3)), now), '3 দিন আগে');
  });

  test('dhakaClock is UTC+6', () {
    expect(dhakaClock(DateTime.utc(2026, 10, 29, 12, 25)), '06:25 PM');
    expect(dhakaClock(DateTime.utc(2026, 10, 28, 18, 5)), '12:05 AM');
  });
}
