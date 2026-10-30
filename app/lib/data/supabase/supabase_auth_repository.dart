import 'dart:async';

import '../../core/validators.dart';
import '../../domain/account_enums.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_gateway.dart';
import 'gateway_errors.dart';
import 'rows.dart';
import 'table_gateway.dart';
import 'value_stream.dart';

/// Spec 13: email OTP sign-in with Supabase, then the merchant owned by this user. Never logs the email or code.
/// deviceId stays null until spec 13a.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({required this._auth, required this._tables, DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  static const resendWait = Duration(seconds: 60);
  static const _ownerKey = 'merchants_owner_id_key';

  final AuthGateway _auth;
  final TableGateway _tables;
  final DateTime Function() _clock;
  final _state = ValueStream<AuthState>(AuthState.signedOut);
  final _lastSent = <String, DateTime>{};
  StreamSubscription<void>? _sub;

  /// Restores a saved session (signed in across restarts) and follows sign-outs from elsewhere.
  Future<void> start() async {
    _sub ??= _auth.changes.listen((_) {
      if (_auth.currentUserId == null && _state.value.status != AuthStatus.codeSent) {
        _state.value = AuthState.signedOut;
      }
    });
    final userId = _auth.currentUserId;
    if (userId == null) return;
    try {
      await _enter(userId, _auth.currentEmail);
    } on OfflineException {
      // Signed in, merchant not known yet: the business-name step decides once online.
      _state.value = AuthState(status: AuthStatus.needsBusinessName, email: _auth.currentEmail);
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _state.close();
  }

  @override
  Stream<AuthState> watch() => _state.watch();

  @override
  Future<AuthResult> sendCode(String email) async {
    final e = normalizeEmail(email);
    if (!isValidEmail(e)) return AuthResult.invalidEmail;
    final now = _clock();
    final last = _lastSent[e];
    if (last != null && now.difference(last) < resendWait) return AuthResult.tooSoon;
    try {
      await _auth.sendOtp(e);
    } on AuthGatewayException catch (x) {
      return switch (x.kind) {
        AuthFailure.badRequest => AuthResult.invalidEmail,
        AuthFailure.rateLimited => AuthResult.tooSoon,
        AuthFailure.invalidCode || AuthFailure.other => AuthResult.offline,
      };
    } on OfflineException {
      return AuthResult.offline;
    }
    _lastSent[e] = now;
    _state.value = AuthState(status: AuthStatus.codeSent, email: e);
    return AuthResult.done;
  }

  @override
  Future<AuthResult> verifyCode(String email, String code) async {
    final e = normalizeEmail(email);
    try {
      await _auth.verifyOtp(e, toEnglishDigits(code.trim()));
      final userId = _auth.currentUserId;
      if (userId == null) return AuthResult.wrongCode;
      await _enter(userId, e);
    } on AuthGatewayException catch (x) {
      return x.kind == AuthFailure.rateLimited ? AuthResult.tooSoon : AuthResult.wrongCode;
    } on OfflineException {
      return AuthResult.offline;
    }
    return AuthResult.done;
  }

  /// found -> signedIn; none -> needsBusinessName.
  Future<void> _enter(String userId, String? email) async {
    final row = await _tables.merchantForUser(userId);
    _state.value = row == null
        ? AuthState(status: AuthStatus.needsBusinessName, email: email)
        : AuthState(status: AuthStatus.signedIn, email: email, merchant: merchantFromRow(row));
  }

  @override
  Future<void> createMerchant(String businessName) async {
    final a = _state.value;
    final userId = _auth.currentUserId;
    if (a.status != AuthStatus.needsBusinessName || userId == null) return;
    try {
      final row = await _tables.insertMerchant(userId, businessName.trim());
      _state.value = a.copyWith(status: AuthStatus.signedIn, merchant: merchantFromRow(row));
    } on TableGatewayException catch (x) {
      // Already has one (e.g. a second tap, or another phone was faster): use it.
      if (x.kind != TableFailure.uniqueViolation || x.constraint != _ownerKey) rethrow;
      await _enter(userId, a.email);
    } on OfflineException {
      // Nothing saved; the business name screen stays and the merchant can try again.
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    _lastSent.clear();
    _state.value = AuthState.signedOut;
  }
}
