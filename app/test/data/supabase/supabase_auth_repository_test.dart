import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/supabase/gateway_errors.dart';
import 'package:verifier/data/supabase/supabase_auth_repository.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/models/auth_state.dart';

import 'fakes.dart';

void main() {
  late FakeAuthGateway auth;
  late FakeTableGateway tables;
  late SupabaseAuthRepository repo;

  setUp(() async {
    auth = FakeAuthGateway();
    tables = FakeTableGateway();
    repo = SupabaseAuthRepository(auth: auth, tables: tables);
    await repo.start();
  });

  Future<AuthState> state() => repo.watch().first;

  group('signIn mapping', () {
    test('username normalized and sent as the internal address; the password as typed', () async {
      expect(await repo.signIn(' Rahim_1 ', 'pass word'), AuthResult.done);
      expect(auth.signIns.single, ('rahim_1@users.bdpay.app', 'pass word'));
      expect((await state()).email, 'rahim_1@users.bdpay.app');
    });

    test('bad username -> invalidUsername; short password -> wrongPassword; no call', () async {
      expect(await repo.signIn('ab', '123456'), AuthResult.invalidUsername);
      expect(await repo.signIn('a b c', '123456'), AuthResult.invalidUsername);
      expect(await repo.signIn('rahim', '12345'), AuthResult.wrongPassword);
      expect(auth.signIns, isEmpty);
    });

    test('gateway failures map to results', () async {
      final cases = {
        const AuthGatewayException(AuthFailure.wrongPassword): AuthResult.wrongPassword,
        const AuthGatewayException(AuthFailure.badRequest): AuthResult.wrongPassword,
        const AuthGatewayException(AuthFailure.rateLimited): AuthResult.tooSoon,
        const AuthGatewayException(AuthFailure.notConfirmed): AuthResult.notConfirmed,
        const AuthGatewayException(AuthFailure.other): AuthResult.offline,
        offline: AuthResult.offline,
      };
      for (final MapEntry(key: error, value: expected) in cases.entries) {
        auth.signInError = error;
        expect(await repo.signIn('rahim', '123456'), expected, reason: '$error');
      }
      expect((await state()).status, AuthStatus.signedOut);
    });
  });

  group('signUp mapping', () {
    test('bad username -> invalidUsername; short password -> weakPassword; no call', () async {
      expect(await repo.signUp('x', '123456'), AuthResult.invalidUsername);
      expect(await repo.signUp('rahim', '123'), AuthResult.weakPassword);
      expect(auth.signUps, isEmpty);
    });

    test('gateway failures map to results', () async {
      final cases = {
        const AuthGatewayException(AuthFailure.userExists): AuthResult.usernameTaken,
        const AuthGatewayException(AuthFailure.weakPassword): AuthResult.weakPassword,
        const AuthGatewayException(AuthFailure.badRequest): AuthResult.invalidUsername,
        const AuthGatewayException(AuthFailure.rateLimited): AuthResult.tooSoon,
        const AuthGatewayException(AuthFailure.notConfirmed): AuthResult.notConfirmed,
        const AuthGatewayException(AuthFailure.other): AuthResult.offline,
        offline: AuthResult.offline,
      };
      for (final MapEntry(key: error, value: expected) in cases.entries) {
        auth.signUpError = error;
        expect(await repo.signUp('rahim', '123456'), expected, reason: '$error');
      }
    });

    test('new account -> needsBusinessName', () async {
      expect(await repo.signUp('Rahim', 'secret1'), AuthResult.done);
      expect(auth.signUps.single, ('rahim@users.bdpay.app', 'secret1'));
      expect((await state()).status, AuthStatus.needsBusinessName);
    });
  });

  group('merchant lookup after login', () {
    test('no merchant -> needsBusinessName', () async {
      expect(await repo.signIn('rahim', '123456'), AuthResult.done);
      expect((await state()).status, AuthStatus.needsBusinessName);
    });

    test('merchant found -> signedIn with it; deviceId stays null', () async {
      tables.merchants['user-1'] = {'id': 'm-9', 'business_name': 'রহিম স্টোর'};
      expect(await repo.signIn('rahim', '123456'), AuthResult.done);
      final s = await state();
      expect(s.status, AuthStatus.signedIn);
      expect(s.merchant?.id, 'm-9');
      expect(s.merchant?.businessName, 'রহিম স্টোর');
      expect(s.deviceId, isNull);
    });

    test('merchant lookup offline -> offline', () async {
      tables.nextError = offline;
      expect(await repo.signIn('rahim', '123456'), AuthResult.offline);
    });
  });

  group('createMerchant', () {
    test('inserts with the current user -> signedIn', () async {
      await repo.signIn('rahim', '123456');
      await repo.createMerchant('  নতুন দোকান ');
      final s = await state();
      expect(s.status, AuthStatus.signedIn);
      expect(s.merchant?.businessName, 'নতুন দোকান');
      expect(tables.merchants['user-1']?['business_name'], 'নতুন দোকান');
    });

    test('already has a merchant (unique owner) -> uses it', () async {
      await repo.signIn('rahim', '123456');
      tables.merchants['user-1'] = {'id': 'm-1', 'business_name': 'আগের দোকান'};
      await repo.createMerchant('নতুন');
      expect((await state()).merchant?.businessName, 'আগের দোকান');
    });

    test('offline -> nothing saved, still needsBusinessName', () async {
      await repo.signIn('rahim', '123456');
      tables.nextError = offline;
      await repo.createMerchant('নতুন');
      expect((await state()).status, AuthStatus.needsBusinessName);
      expect(tables.merchants, isEmpty);
    });
  });

  group('session across restarts', () {
    test('a saved session with a merchant -> signedIn at start, no new code', () async {
      final a = FakeAuthGateway()
        ..userId = 'u-7'
        ..email = 'x@y.co';
      final t = FakeTableGateway()..merchants['u-7'] = {'id': 'm-7', 'business_name': 'দোকান'};
      final r = SupabaseAuthRepository(auth: a, tables: t);
      await r.start();
      final s = await r.watch().first;
      expect(s.status, AuthStatus.signedIn);
      expect(s.email, 'x@y.co');
      expect(a.signIns, isEmpty);
    });

    test('edge: killed during the business name step -> needsBusinessName again', () async {
      final a = FakeAuthGateway()
        ..userId = 'u-8'
        ..email = 'x@y.co';
      final r = SupabaseAuthRepository(auth: a, tables: FakeTableGateway());
      await r.start();
      expect((await r.watch().first).status, AuthStatus.needsBusinessName);
    });

    test('no saved session -> signedOut', () async {
      expect((await state()).status, AuthStatus.signedOut);
    });
  });

  test('signOut -> gateway sign-out and signedOut', () async {
    tables.merchants['user-1'] = {'id': 'm-1', 'business_name': 'দোকান'};
    await repo.signIn('rahim', '123456');
    await repo.signOut();
    expect(auth.signOuts, 1);
    expect((await state()).status, AuthStatus.signedOut);
  });

  test('a sign-out from elsewhere (session gone) -> signedOut', () async {
    tables.merchants['user-1'] = {'id': 'm-1', 'business_name': 'দোকান'};
    await repo.signIn('rahim', '123456');
    auth.userId = null;
    auth.emitChange();
    await pumpEventQueue();
    expect((await state()).status, AuthStatus.signedOut);
  });
}
