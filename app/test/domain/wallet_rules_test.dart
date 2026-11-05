import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/wallet.dart';
import 'package:verifier/domain/wallet_rules.dart';

Wallet w(
  String id,
  MfsOperator op,
  String number, {
  SimSlot sim = SimSlot.sim1,
  bool active = true,
}) =>
    Wallet(
      id: id,
      operator: op,
      walletNumber: number,
      accountType: AccountType.merchant,
      simSlot: sim,
      isActive: active,
    );

void main() {
  final existing = [
    w('1', MfsOperator.bkash, '01700000001'),
    w('2', MfsOperator.nagad, '01700000002', active: false),
  ];

  test('valid new wallet -> done', () {
    expect(checkWallet(existing, w('', MfsOperator.bkash, '01811222333', sim: SimSlot.sim2)), AddWalletResult.done);
  });

  test('invalid number -> invalidNumber', () {
    expect(checkWallet(existing, w('', MfsOperator.bkash, '01211222333')), AddWalletResult.invalidNumber);
  });

  test('same operator + number -> duplicate, also when the old one is inactive', () {
    expect(checkWallet(existing, w('', MfsOperator.bkash, '01700000001', sim: SimSlot.sim2)),
        AddWalletResult.duplicate);
    expect(checkWallet(existing, w('', MfsOperator.nagad, '01700000002', sim: SimSlot.sim2)),
        AddWalletResult.duplicate);
  });

  test('same number for another operator is allowed (D9)', () {
    expect(checkWallet(existing, w('', MfsOperator.upay, '01700000001', sim: SimSlot.sim2)), AddWalletResult.done);
  });

  test('two active wallets, same operator, same SIM -> simTaken', () {
    expect(checkWallet(existing, w('', MfsOperator.bkash, '01811222333')), AddWalletResult.simTaken);
  });

  test('simTaken ignores unknown SIM, inactive wallets and other operators', () {
    expect(checkWallet(existing, w('', MfsOperator.bkash, '01811222333', sim: SimSlot.unknown)),
        AddWalletResult.done);
    expect(checkWallet(existing, w('', MfsOperator.bkash, '01811222333', active: false)), AddWalletResult.done);
    expect(checkWallet(existing, w('', MfsOperator.nagad, '01811222333')), AddWalletResult.done);
  });

  test('editing a wallet does not clash with itself', () {
    expect(checkWallet(existing, w('1', MfsOperator.bkash, '01700000001')), AddWalletResult.done);
  });
}
