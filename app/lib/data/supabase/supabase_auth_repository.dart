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

/// Spec 16: username + password sign-in with Supabase, then the merchant owned by this user (spec 13).
/// Never logs the username or the password.
/// deviceId stays null until spec 13a.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({required this._auth, required this._tables});

  static const _ownerKey = 'merchants_owner_id_key';

  final AuthGateway _auth;
  final TableGateway _tables;
  final _state = ValueStream<AuthState>(AuthState.signedOut);
  StreamSubscription<void>? _sub;

  /// Restores a saved session (signed in across restarts) and follows sign-outs from elsewhere.
  Future<void> start() async {
    _sub ??= _auth.changes.listen((_) {
      if (_auth.currentUserId == null) {
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
  Future<AuthResult> signIn(String username, String password) async {
    final u = normalizeUsername(username);
    if (!isValidUsername(u)) return AuthResult.invalidUsername;
    if (password.length < minPasswordLength) return AuthResult.wrongPassword;
    final email = usernameToEmail(u);
    return _run(() => _auth.signIn(email, password), email, (kind) => switch (kind) {
          AuthFailure.wrongPassword || AuthFailure.badRequest => AuthResult.wrongPassword,
          AuthFailure.rateLimited => AuthResult.tooSoon,
          AuthFailure.notConfirmed => AuthResult.notConfirmed,
          _ => AuthResult.offline,
        });
  }

  @override
  Future<AuthResult> signUp(String username, String password) async {
    final u = normalizeUsername(username);
    if (!isValidUsername(u)) return AuthResult.invalidUsername;
    if (password.length < minPasswordLength) return AuthResult.weakPassword;
    final email = usernameToEmail(u);
    return _run(() => _auth.signUp(email, password), email, (kind) => switch (kind) {
          AuthFailure.userExists => AuthResult.usernameTaken,
          AuthFailure.weakPassword => AuthResult.weakPassword,
          AuthFailure.badRequest => AuthResult.invalidUsername,
          AuthFailure.rateLimited => AuthResult.tooSoon,
          AuthFailure.notConfirmed => AuthResult.notConfirmed,
          _ => AuthResult.offline,
        });
  }

  /// Calls the gateway, then looks up the merchant of the signed-in user.
  Future<AuthResult> _run(
    Future<void> Function() call,
    String email,
    AuthResult Function(AuthFailure) mapFailure,
  ) async {
    try {
      await call();
      final userId = _auth.currentUserId;
      if (userId == null) return AuthResult.offline;
      await _enter(userId, email);
    } on AuthGatewayException catch (x) {
      return mapFailure(x.kind);
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
    _state.value = AuthState.signedOut;
  }
}
