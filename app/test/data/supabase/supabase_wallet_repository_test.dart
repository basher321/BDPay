import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/supabase/gateway_errors.dart';
import 'package:verifier/data/supabase/supabase_wallet_repository.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/auth_state.dart';
import 'package:verifier/domain/models/merchant.dart';
import 'package:verifier/domain/models/wallet.dart';
import 'package:verifier/domain/repositories/repository_errors.dart';

import 'fakes.dart';

const _signedIn = AuthState(
  status: AuthStatus.signedIn,
  email: 'a@b.co',
  merchant: Merchant(id: 'm-1', businessName: 'দোকান'),
);

Wallet _w({String number = '01711222333', MfsOperator op = MfsOperator.bkash, SimSlot sim = SimSlot.sim1}) => Wallet(
      id: '',
      operator: op,
      walletNumber: number,
      accountType: AccountType.merchant,
      label: '  দোকান  ',
      simSlot: sim,
      isActive: true,
    );

void main() {
  late FakeTableGateway tables;
  late StreamController<AuthState> auth;
  late FakeForeground fg;
  late SupabaseWalletRepository repo;

  setUp(() async {
    tables = FakeTableGateway();
    auth = StreamController<AuthState>.broadcast();
    fg = FakeForeground();
    repo = SupabaseWalletRepository(tables: tables, auth: auth.stream, foreground: fg)..start();
    auth.add(_signedIn);
    await pumpEventQueue();
  });

  Future<List<Wallet>> wallets() => repo.watch().first;

  test('add: the app validates first (normalized number, trimmed label), then the row is listed', () async {
    expect(await repo.add(_w(number: '০১৭১১-২২২ ৩৩৩')), AddWalletResult.done);
    expect(tables.wallets.single['wallet_number'], '01711222333');
    expect(tables.wallets.single['merchant_id'], 'm-1');
    final list = await wallets();
    expect(list.single.walletNumber, '01711222333');
    expect(list.single.label, 'দোকান');
  });

  test('add: an invalid number -> invalidNumber without a database call', () async {
    expect(await repo.add(_w(number: '0171122')), AddWalletResult.invalidNumber);
    expect(tables.wallets, isEmpty);
  });

  test('database unique (operator, wallet_number) -> duplicate', () async {
    tables.nextError = const TableGatewayException(
      TableFailure.uniqueViolation,
      constraint: SupabaseWalletRepository.numberUnique,
    );
    expect(await repo.add(_w()), AddWalletResult.duplicate);
  });

  test('database active-SIM partial unique -> simTaken (add, update and setActive)', () async {
    const sim = TableGatewayException(TableFailure.uniqueViolation, constraint: SupabaseWalletRepository.simUnique);
    tables.nextError = sim;
    expect(await repo.add(_w()), AddWalletResult.simTaken);
    await repo.add(_w());
    final id = tables.wallets.single['id'] as String;
    tables.nextError = sim;
    expect(await repo.update(_w().copyWith(id: id, simSlot: SimSlot.sim2)), AddWalletResult.simTaken);
    tables.nextError = sim;
    expect(await repo.setActive(id, true), AddWalletResult.simTaken);
  });

  test('check violation -> invalidNumber', () async {
    tables.nextError = const TableGatewayException(TableFailure.checkViolation);
    expect(await repo.add(_w()), AddWalletResult.invalidNumber);
  });

  test('no network -> OfflineError and nothing changes', () async {
    await repo.add(_w());
    final before = await wallets();
    tables.nextError = offline;
    await expectLater(repo.add(_w(number: '01811222333')), throwsA(isA<OfflineError>()));
    expect(await wallets(), before);
    expect(tables.wallets.length, 1);
  });

  test('update changes account type, label and SIM only; setActive changes isActive', () async {
    await repo.add(_w());
    final id = tables.wallets.single['id'] as String;
    await repo.update(_w(number: '01999999999', op: MfsOperator.nagad, sim: SimSlot.sim2).copyWith(id: id));
    final row = tables.wallets.single;
    expect(row['wallet_number'], '01711222333');
    expect(row['operator'], 'bkash');
    expect(row['sim_slot'], 'sim2');
    await repo.setActive(id, false);
    expect((await wallets()).single.isActive, isFalse);
  });

  test('watch refetches after every write and when the app comes to the front', () async {
    final start = tables.listCalls;
    await repo.add(_w());
    expect(tables.listCalls, start + 1);
    fg.resume();
    await pumpEventQueue();
    expect(tables.listCalls, start + 2);
  });

  test('rows are exactly what the database holds (another phone added one)', () async {
    tables.wallets.add({
      'id': 'w-x',
      'merchant_id': 'm-1',
      'operator': 'rocket',
      'wallet_number': '017000000031',
      'account_type': 'agent',
      'label': null,
      'sim_slot': 'sim2',
      'is_active': true,
    });
    fg.resume();
    await pumpEventQueue();
    final w = (await wallets()).single;
    expect(w.operator, MfsOperator.rocket);
    expect(w.accountType, AccountType.agent);
  });

  test('sign-out clears the list', () async {
    await repo.add(_w());
    auth.add(AuthState.signedOut);
    await pumpEventQueue();
    expect(await wallets(), isEmpty);
  });
}
