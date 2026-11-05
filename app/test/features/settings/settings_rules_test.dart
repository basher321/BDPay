import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/wallet.dart';
import 'package:verifier/features/settings/settings_rules.dart';

Wallet w(String id, {required bool active}) => Wallet(
      id: id,
      operator: MfsOperator.bkash,
      walletNumber: '0170000000$id',
      accountType: AccountType.merchant,
      simSlot: SimSlot.unknown,
      isActive: active,
    );

void main() {
  test('isLastActiveWallet: only when it is the one active wallet', () {
    expect(isLastActiveWallet([w('1', active: true)], '1'), isTrue);
    expect(isLastActiveWallet([w('1', active: true), w('2', active: false)], '1'), isTrue);
    expect(isLastActiveWallet([w('1', active: true), w('2', active: true)], '1'), isFalse);
    expect(isLastActiveWallet([w('1', active: true), w('2', active: false)], '2'), isFalse);
  });

  test('logoutBlockedCount counts queued, sending and failed', () {
    final sample = buildSampleTransactions(DateTime.utc(2026, 10, 29, 6));
    expect(logoutBlockedCount(sample), 2);
    final withSending = [sample.first.copyWith(syncStatus: SyncStatus.sending), ...sample.skip(1)];
    expect(logoutBlockedCount(withSending), 3);
    expect(logoutBlockedCount(const []), 0);
  });
}
