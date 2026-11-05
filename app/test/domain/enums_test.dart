import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/enums.dart';

void main() {
  test('toWire / fromWire round trip for every value', () {
    for (final v in MfsOperator.values) {
      expect(MfsOperator.fromWire(v.toWire()), v);
    }
    for (final v in VerifyStatus.values) {
      expect(VerifyStatus.fromWire(v.toWire()), v);
    }
    for (final v in SyncStatus.values) {
      expect(SyncStatus.fromWire(v.toWire()), v);
    }
    for (final v in TxKind.values) {
      expect(TxKind.fromWire(v.toWire()), v);
    }
  });

  test('fromWire with an unknown value throws', () {
    expect(() => MfsOperator.fromWire('foo'), throwsFormatException);
    expect(() => VerifyStatus.fromWire('foo'), throwsFormatException);
    expect(() => SyncStatus.fromWire('foo'), throwsFormatException);
    expect(() => TxKind.fromWire('foo'), throwsFormatException);
  });
}
