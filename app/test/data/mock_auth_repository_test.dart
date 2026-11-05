import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/account_enums.dart';

import 'mock_account_test_helpers.dart';

void main() {
  test('the app starts signedOut', () async {
    final m = AccountMocks();
    expect((await m.auth.watch().first).status, AuthStatus.signedOut);
  });

  test('signIn: bad username -> invalidUsername; short or wrong password -> wrongPassword', () async {
    final m = AccountMocks();
    expect(await m.auth.signIn('ab', '123456'), AuthResult.invalidUsername);
    expect(await m.auth.signIn('demo', '123'), AuthResult.wrongPassword);
    expect(await m.auth.signIn('demo', '654321'), AuthResult.wrongPassword);
    expect(await m.auth.signIn('nobody', '123456'), AuthResult.wrongPassword);
    expect(m.data.auth.value.status, AuthStatus.signedOut);
  });

  test('signIn / signUp offline -> offline', () async {
    final m = AccountMocks();
    await m.setOnline(false);
    expect(await m.auth.signIn('demo', '123456'), AuthResult.offline);
    expect(await m.auth.signUp('newshop', '123456'), AuthResult.offline);
  });

  test('signUp: short password -> weakPassword; a taken username -> usernameTaken', () async {
    final m = AccountMocks();
    expect(await m.auth.signUp('newshop', '123'), AuthResult.weakPassword);
    expect(await m.auth.signUp('demo', '123456'), AuthResult.usernameTaken);
    expect(await m.auth.signUp('NewShop', '123456'), AuthResult.done);
    await m.auth.signOut();
    expect(await m.auth.signUp('newshop', '999999'), AuthResult.usernameTaken);
    expect(await m.auth.signIn('newshop', '123456'), AuthResult.done);
  });

  test('a new account goes to needsBusinessName, then createMerchant signs in with no wallets and no store', () async {
    final m = AccountMocks();
    await m.signIn('newshop');
    expect(m.data.auth.value.status, AuthStatus.needsBusinessName);
    await m.auth.createMerchant('  আমার দোকান ');
    final a = m.data.auth.value;
    expect(a.status, AuthStatus.signedIn);
    expect(a.merchant!.businessName, 'আমার দোকান');
    expect(a.deviceId, isNotNull);
    expect(await m.wallets.watch().first, isEmpty);
    expect(await m.store.watch().first, isNull);
  });

  test('demo / 123456 goes straight to signedIn as "নমুনা স্টোর" on BDP-A1', () async {
    final m = AccountMocks();
    await m.signIn('demo');
    final a = m.data.auth.value;
    expect(a.status, AuthStatus.signedIn);
    expect(a.merchant!.businessName, 'নমুনা স্টোর');
    expect(a.deviceId, 'BDP-A1');
  });

  test('signing out and in again as demo shows the same mock data', () async {
    final m = AccountMocks();
    await m.signIn('demo');
    await m.wallets.setActive('w_demo_4', false);
    await m.auth.signOut();
    expect(m.data.auth.value.status, AuthStatus.signedOut);
    expect(await m.wallets.watch().first, isEmpty);
    await m.signIn('demo');
    final wallets = await m.wallets.watch().first;
    expect(wallets.length, 4);
    expect(wallets.firstWhere((w) => w.id == 'w_demo_4').isActive, isFalse);
  });
}
