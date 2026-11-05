import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/shopify_store.dart';
import 'package:verifier/domain/models/wallet.dart';
import 'package:verifier/features/home/setup_status.dart';

Wallet w({required bool active}) => Wallet(
      id: '1',
      operator: MfsOperator.bkash,
      walletNumber: '01700000001',
      accountType: AccountType.merchant,
      simSlot: SimSlot.sim1,
      isActive: active,
    );

void main() {
  final store = ShopifyStore(shopDomain: 'a.myshopify.com', connectedAt: DateTime.utc(2026));

  test('shown when there is no active wallet OR no store; hidden when both are done', () {
    expect(setupStatus(const [], null).show, isTrue);
    expect(setupStatus([w(active: true)], null).show, isTrue);
    expect(setupStatus(const [], store).show, isTrue);
    expect(setupStatus([w(active: false)], store).show, isTrue);
    expect(setupStatus([w(active: true)], store).show, isFalse);
  });

  test('row states', () {
    final s = setupStatus([w(active: false)], store);
    expect(s.hasActiveWallet, isFalse);
    expect(s.hasStore, isTrue);
  });
}
