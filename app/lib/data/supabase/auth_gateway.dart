import 'package:supabase_flutter/supabase_flutter.dart';

import 'gateway_errors.dart';

/// Email OTP sign-in. Thin: no app rules here, only calls and error translation.
abstract interface class AuthGateway {
  String? get currentUserId;

  String? get currentEmail;

  /// Fires on every sign-in, sign-out and token change.
  Stream<void> get changes;

  /// Throws [AuthGatewayException] or [OfflineException].
  Future<void> sendOtp(String email);

  /// Throws [AuthGatewayException] or [OfflineException].
  Future<void> verifyOtp(String email, String code);

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
  Future<void> sendOtp(String email) => _guard(() => _auth.signInWithOtp(email: email, shouldCreateUser: true));

  @override
  Future<void> verifyOtp(String email, String code) =>
      _guard(() => _auth.verifyOTP(email: email, token: code, type: OtpType.email));

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

/// Supabase Auth status + error code -> [AuthFailure] (plan 13 section 3).
AuthFailure authFailureOf(String? status, String? code) {
  if (status == '429' || code == 'over_email_send_rate_limit' || code == 'over_request_rate_limit') {
    return AuthFailure.rateLimited;
  }
  if (code == 'otp_expired' || code == 'invalid_credentials' || status == '401' || status == '403') {
    return AuthFailure.invalidCode;
  }
  if (code == 'email_address_invalid' || code == 'validation_failed' || status == '400' || status == '422') {
    return AuthFailure.badRequest;
  }
  return AuthFailure.other;
}
