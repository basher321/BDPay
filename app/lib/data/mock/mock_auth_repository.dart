import '../../core/validators.dart';
import '../../domain/account_enums.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/models/merchant.dart';
import '../../domain/repositories/auth_repository.dart';
import 'mock_account_data.dart';

/// MOCK - replaced in spec 13 (real email login). The code is always "123456".
/// Never logs the email or the code.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._data);

  static const _mockCode = '123456';
  static const resendWait = Duration(seconds: 60);

  final MockAccountData _data;
  final _lastSent = <String, DateTime>{};
  int _newMerchants = 0;

  @override
  Stream<AuthState> watch() => _data.auth.watch();

  @override
  Future<AuthResult> sendCode(String email) async {
    final e = normalizeEmail(email);
    if (!isValidEmail(e)) return AuthResult.invalidEmail;
    if (!_data.online) return AuthResult.offline;
    final now = _data.clock();
    final last = _lastSent[e];
    if (last != null && now.difference(last) < resendWait) return AuthResult.tooSoon;
    _lastSent[e] = now;
    _data.auth.value = AuthState(status: AuthStatus.codeSent, email: e);
    return AuthResult.done;
  }

  @override
  Future<AuthResult> verifyCode(String email, String code) async {
    if (toEnglishDigits(code.trim()) != _mockCode) return AuthResult.wrongCode;
    final e = normalizeEmail(email);
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
    return AuthResult.done;
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
