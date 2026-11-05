import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/account_enums.dart';

void main() {
  test('toWire / fromWire round trip for every value', () {
    for (final v in AccountType.values) {
      expect(AccountType.fromWire(v.toWire()), v);
    }
    for (final v in SimSlot.values) {
      expect(SimSlot.fromWire(v.toWire()), v);
    }
    for (final v in AuthStatus.values) {
      expect(AuthStatus.fromWire(v.toWire()), v);
    }
    for (final v in AuthResult.values) {
      expect(AuthResult.fromWire(v.toWire()), v);
    }
    for (final v in AddWalletResult.values) {
      expect(AddWalletResult.fromWire(v.toWire()), v);
    }
    for (final v in ConnectResult.values) {
      expect(ConnectResult.fromWire(v.toWire()), v);
    }
  });

  test('wire names are the spec values', () {
    expect(AccountType.values.map((v) => v.toWire()), ['merchant', 'agent']);
    expect(SimSlot.values.map((v) => v.toWire()), ['sim1', 'sim2', 'unknown']);
  });

  test('fromWire with an unknown value throws', () {
    expect(() => AccountType.fromWire('personal'), throwsFormatException);
    expect(() => SimSlot.fromWire('sim3'), throwsFormatException);
    expect(() => AuthStatus.fromWire('foo'), throwsFormatException);
    expect(() => AuthResult.fromWire('foo'), throwsFormatException);
    expect(() => AddWalletResult.fromWire('foo'), throwsFormatException);
    expect(() => ConnectResult.fromWire('foo'), throwsFormatException);
  });
}
