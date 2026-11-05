import '../../core/validators.dart';
import '../../domain/account_enums.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/models/merchant.dart';
import '../../domain/repositories/auth_repository.dart';
import 'mock_account_data.dart';

/// MOCK - the demo build and tests. Spec 16: username + password; "demo" / "123456" is built in.
/// Passwords live only in memory and are never logged.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._data);

  final MockAccountData _data;
  final _passwords = <String, String>{demoEmail: demoPassword};
  int _newMerchants = 0;

  @override
  Stream<AuthState> watch() => _data.auth.watch();

  @override
  Future<AuthResult> signIn(String username, String password) async {
    final u = normalizeUsername(username);
    if (!isValidUsername(u)) return AuthResult.invalidUsername;
    if (password.length < minPasswordLength) return AuthResult.wrongPassword;
    if (!_data.online) return AuthResult.offline;
    final e = usernameToEmail(u);
    if (_passwords[e] != password) return AuthResult.wrongPassword;
    _enter(e);
    return AuthResult.done;
  }

  @override
  Future<AuthResult> signUp(String username, String password) async {
    final u = normalizeUsername(username);
    if (!isValidUsername(u)) return AuthResult.invalidUsername;
    if (password.length < minPasswordLength) return AuthResult.weakPassword;
    if (!_data.online) return AuthResult.offline;
    final e = usernameToEmail(u);
    if (_passwords.containsKey(e)) return AuthResult.usernameTaken;
    _passwords[e] = password;
    _enter(e);
    return AuthResult.done;
  }

  void _enter(String e) {
    if (e == demoEmail) _data.accounts.putIfAbsent(e, buildDemoMerchant);
    final account = _data.accounts[e];
    _data.auth.value = account == null
        ? AuthState(status: AuthStatus.needsBusinessName, email: e)
        : AuthState(
            status: AuthStatus.signedIn,
            email: e,
            merchant: account.merchant,
            deviceId: account.deviceId,
          );
    _data.changed();
  }

  @override
  Future<void> createMerchant(String businessName) async {
    final a = _data.auth.value;
    if (a.status != AuthStatus.needsBusinessName || a.email == null) return;
    _newMerchants++;
    final account = MockMerchantData(
      merchant: Merchant(id: _data.newId('m'), businessName: businessName.trim()),
      deviceId: 'BDP-N$_newMerchants',
    );
    _data.accounts[a.email!] = account;
    _data.auth.value = a.copyWith(
      status: AuthStatus.signedIn,
      merchant: account.merchant,
      deviceId: account.deviceId,
    );
    _data.changed();
  }

  @override
  Future<void> signOut() async {
    _data.auth.value = AuthState.signedOut;
    _data.changed();
  }
}
