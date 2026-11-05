import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/wallet.dart';

import 'mock_account_test_helpers.dart';

Wallet input(MfsOperator op, String number, {SimSlot sim = SimSlot.sim1, String? label}) => Wallet(
      id: '',
      operator: op,
      walletNumber: number,
      accountType: AccountType.merchant,
      label: label,
      simSlot: sim,
      isActive: true,
    );

void main() {
  test('demo wallets after sign-in: 4 active, as in the spec', () async {
    final m = AccountMocks(demoSignedIn: true);
    final list = await m.wallets.watch().first;
    expect(list.map((w) => '${w.operator.name} ${w.walletNumber} ${w.accountType.name} ${w.simSlot.name}'), [
      'bkash 01700000001 merchant sim1',
      'nagad 01700000002 merchant sim1',
      'rocket 017000000031 merchant sim2',
      'upay 01700000004 merchant sim2',
    ]);
    expect(list.every((w) => w.isActive), isTrue);
  });

  test('add stores the normalised number and a new id', () async {
    final m = AccountMocks(demoSignedIn: true);
    expect(await m.wallets.add(input(MfsOperator.bkash, '+880 1811-222333', sim: SimSlot.sim2, label: ' দোকান ')),
        AddWalletResult.done);
    final added = (await m.wallets.watch().first).last;
    expect(added.walletNumber, '01811222333');
    expect(added.id, isNotEmpty);
    expect(added.label, 'দোকান');
  });

  test('add results: invalidNumber, duplicate, simTaken', () async {
    final m = AccountMocks(demoSignedIn: true);
    expect(await m.wallets.add(input(MfsOperator.bkash, '01211222333')), AddWalletResult.invalidNumber);
    expect(await m.wallets.add(input(MfsOperator.nagad, '01700000002')), AddWalletResult.duplicate);
    expect(await m.wallets.add(input(MfsOperator.bkash, '01811222333')), AddWalletResult.simTaken);
    expect((await m.wallets.watch().first).length, 4);
  });

  test('an existing inactive wallet is still a duplicate', () async {
    final m = AccountMocks(demoSignedIn: true);
    await m.wallets.setActive('w_demo_2', false);
    expect(await m.wallets.add(input(MfsOperator.nagad, '01700000002', sim: SimSlot.sim2)),
        AddWalletResult.duplicate);
  });

  test('update keeps operator, number and isActive; can return simTaken', () async {
    final m = AccountMocks(demoSignedIn: true);
    final rocket = (await m.wallets.watch().first)[2];
    expect(
      await m.wallets.update(rocket.copyWith(operator: MfsOperator.bkash, walletNumber: '01999999999',
          accountType: AccountType.agent, label: 'x')),
      AddWalletResult.done,
    );
    final updated = (await m.wallets.watch().first)[2];
    expect(updated.operator, MfsOperator.rocket);
    expect(updated.walletNumber, '017000000031');
    expect(updated.accountType, AccountType.agent);
    expect(updated.label, 'x');

    await m.wallets.add(input(MfsOperator.bkash, '01811222333', sim: SimSlot.sim2));
    final second = (await m.wallets.watch().first).last;
    expect(await m.wallets.update(second.copyWith(simSlot: SimSlot.sim1)), AddWalletResult.simTaken);
  });

  test('setActive on returns simTaken on a clash (D7); off always works', () async {
    final m = AccountMocks(demoSignedIn: true);
    await m.wallets.setActive('w_demo_1', false);
    await m.wallets.add(input(MfsOperator.bkash, '01811222333'));
    expect(await m.wallets.setActive('w_demo_1', true), AddWalletResult.simTaken);
    final list = await m.wallets.watch().first;
    expect(list.firstWhere((w) => w.id == 'w_demo_1').isActive, isFalse);
  });

  test('a new merchant starts with no wallets', () async {
    final m = AccountMocks();
    await m.signIn('newshop');
    await m.auth.createMerchant('দোকান');
    expect(await m.wallets.watch().first, isEmpty);
  });
}
