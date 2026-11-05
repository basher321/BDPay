import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/parser/parse_sms.dart';

void main() {
  test('amount text -> poisha with whole-number math', () {
    expect(amountTextToPoisha('1,250.50'), 125050);
    expect(amountTextToPoisha('1,250.5'), 125050);
    expect(amountTextToPoisha('1,250'), 125000);
    expect(amountTextToPoisha('0.5'), 50);
    expect(amountTextToPoisha('15,340.50'), 1534050);
  });

  test('bad amount text gives null and never throws', () {
    expect(amountTextToPoisha(''), isNull);
    expect(amountTextToPoisha('1.234'), isNull);
    expect(amountTextToPoisha('abc'), isNull);
    expect(amountTextToPoisha('.5'), isNull);
    expect(amountTextToPoisha('99999999999999'), isNull);
  });

  test('normalizeSmsBody: Bangla digits and Unicode spaces', () {
    expect(normalizeSmsBody('৳ ১,২৫০.০০'), '৳ 1,250.00');
  });
}
