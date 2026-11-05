import 'package:supabase_flutter/supabase_flutter.dart';

import 'gateway_errors.dart';

/// Spec 16: email + password sign-in (the email is the internal address of a username).
/// Thin: no app rules here, only calls and error translation. Never logs the password.
abstract interface class AuthGateway {
  String? get currentUserId;

  String? get currentEmail;

  /// Fires on every sign-in, sign-out and token change.
  Stream<void> get changes;

  /// Throws [AuthGatewayException] or [OfflineException].
  Future<void> signIn(String email, String password);

  /// Throws [AuthGatewayException] or [OfflineException]. No session afterwards -> notConfirmed.
  Future<void> signUp(String email, String password);

  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._auth);

  final GoTrueClient _auth;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  String? get currentEmail => _auth.currentUser?.email;

  @override
  Stream<void> get changes => _auth.onAuthStateChange.map((_) {});

  @override
  Future<void> signIn(String email, String password) =>
      _guard(() => _auth.signInWithPassword(email: email, password: password));

  @override
  Future<void> signUp(String email, String password) => _guard(() async {
        final r = await _auth.signUp(email: email, password: password);
        // "Confirm email" is on in the project: the account exists but cannot log in.
        if (r.session == null) throw const AuthGatewayException(AuthFailure.notConfirmed);
        return r;
      });

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      // Signing out locally always works; a failed server call is not shown.
      if (!isOfflineError(e) && e is! AuthException) rethrow;
    }
  }

  static Future<void> _guard(Future<Object?> Function() call) async {
    try {
      await call();
    } on AuthGatewayException {
      rethrow;
    } on AuthRetryableFetchException {
      throw const OfflineException();
    } on AuthException catch (e) {
      throw AuthGatewayException(authFailureOf(e.statusCode, e.code));
    } catch (e) {
      if (isOfflineError(e)) throw const OfflineException();
      rethrow;
    }
  }
}

/// Supabase Auth status + error code -> [AuthFailure] (plan 16 step 4).
AuthFailure authFailureOf(String? status, String? code) {
  if (status == '429' || code == 'over_email_send_rate_limit' || code == 'over_request_rate_limit') {
    return AuthFailure.rateLimited;
  }
  if (code == 'user_already_exists' || code == 'email_exists') return AuthFailure.userExists;
  if (code == 'weak_password') return AuthFailure.weakPassword;
  if (code == 'email_not_confirmed') return AuthFailure.notConfirmed;
  if (code == 'invalid_credentials' || status == '401' || status == '403') return AuthFailure.wrongPassword;
  if (code == 'email_address_invalid' || code == 'validation_failed' || status == '400' || status == '422') {
    return AuthFailure.badRequest;
  }
  return AuthFailure.other;
}
