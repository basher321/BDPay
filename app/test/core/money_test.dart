import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/money.dart';

void main() {
  test('formats poisha as taka', () {
    expect(formatPoisha(125050), '৳ 1,250.50');
    expect(formatPoisha(0), '৳ 0.00');
    expect(formatPoisha(123456789), '৳ 1,234,567.89');
  });

  test('negative poisha throws ArgumentError', () {
    expect(() => formatPoisha(-1), throwsArgumentError);
  });
}
