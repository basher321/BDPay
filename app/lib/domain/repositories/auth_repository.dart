import '../account_enums.dart';
import '../models/auth_state.dart';

abstract interface class AuthRepository {
  Stream<AuthState> watch();

  Future<AuthResult> sendCode(String email);

  Future<AuthResult> verifyCode(String email, String code);

  Future<void> createMerchant(String businessName);

  Future<void> signOut();
}
