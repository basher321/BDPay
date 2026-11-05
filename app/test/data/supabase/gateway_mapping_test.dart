import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/app_config.dart';
import 'package:verifier/data/supabase/auth_gateway.dart';
import 'package:verifier/data/supabase/gateway_errors.dart';
import 'package:verifier/data/supabase/table_gateway.dart';

void main() {
  group('authFailureOf (plan 16 step 4)', () {
    test('rate limits -> rateLimited', () {
      expect(authFailureOf('429', null), AuthFailure.rateLimited);
      expect(authFailureOf(null, 'over_email_send_rate_limit'), AuthFailure.rateLimited);
      expect(authFailureOf('400', 'over_request_rate_limit'), AuthFailure.rateLimited);
    });
    test('spec 16 codes: wrong password, taken, weak, not confirmed', () {
      expect(authFailureOf('400', 'invalid_credentials'), AuthFailure.wrongPassword);
      expect(authFailureOf('401', null), AuthFailure.wrongPassword);
      expect(authFailureOf('422', 'user_already_exists'), AuthFailure.userExists);
      expect(authFailureOf('422', 'email_exists'), AuthFailure.userExists);
      expect(authFailureOf('422', 'weak_password'), AuthFailure.weakPassword);
      expect(authFailureOf('400', 'email_not_confirmed'), AuthFailure.notConfirmed);
    });
    test('bad email / validation -> badRequest', () {
      expect(authFailureOf('400', 'email_address_invalid'), AuthFailure.badRequest);
      expect(authFailureOf('422', 'validation_failed'), AuthFailure.badRequest);
      expect(authFailureOf('400', null), AuthFailure.badRequest);
    });
    test('anything else -> other', () {
      expect(authFailureOf('500', 'unexpected_failure'), AuthFailure.other);
      expect(authFailureOf(null, null), AuthFailure.other);
    });
  });

  group('tableErrorOf', () {
    test('23505 keeps the constraint name, not the message', () {
      final e = tableErrorOf(
        '23505',
        'duplicate key value violates unique constraint "wallets_operator_wallet_number_key"',
      );
      expect(e.kind, TableFailure.uniqueViolation);
      expect(e.constraint, 'wallets_operator_wallet_number_key');
      expect(e.toString(), isNot(contains('duplicate key')));
    });
    test('23514 check, 42501 denied, other codes other', () {
      expect(tableErrorOf('23514', 'new row violates check constraint "wallets_number_check"').kind,
          TableFailure.checkViolation);
      expect(tableErrorOf('42501', 'permission denied').kind, TableFailure.denied);
      expect(tableErrorOf('PGRST116', 'x').kind, TableFailure.other);
    });
  });

  test('isOfflineError: socket, timeout, http and a ClientException-named type', () {
    expect(isOfflineError(const SocketException('x')), isTrue);
    expect(isOfflineError(TimeoutException('x')), isTrue);
    expect(isOfflineError(const HttpException('x')), isTrue);
    expect(isOfflineError(ClientException()), isTrue);
    expect(isOfflineError(StateError('x')), isFalse);
  });

  group('AppConfig', () {
    test('complete only with an http(s) URL and a key', () {
      expect(const AppConfig(supabaseUrl: 'http://10.0.2.2:54321', anonKey: 'k').isComplete, isTrue);
      expect(const AppConfig(supabaseUrl: 'https://x.example', anonKey: 'k').isComplete, isTrue);
      expect(const AppConfig(supabaseUrl: '', anonKey: 'k').isComplete, isFalse);
      expect(const AppConfig(supabaseUrl: 'http://10.0.2.2:54321', anonKey: '').isComplete, isFalse);
      expect(const AppConfig(supabaseUrl: 'not a url', anonKey: 'k').isComplete, isFalse);
      expect(AppConfig.none.isComplete, isFalse);
    });
    test('functionsUrl = SUPABASE_URL + /functions/v1', () {
      expect(const AppConfig(supabaseUrl: 'http://10.0.2.2:54321', anonKey: 'k').functionsUrl,
          'http://10.0.2.2:54321/functions/v1');
      expect(const AppConfig(supabaseUrl: 'http://10.0.2.2:54321/', anonKey: 'k').functionsUrl,
          'http://10.0.2.2:54321/functions/v1');
    });
    test('tests run without dart-defines', () {
      expect(AppConfig.fromDefines.isComplete, isFalse);
    });
  });
}

/// Stands in for package:http's ClientException (matched by type name).
class ClientException implements Exception {}
