import '../account_enums.dart';
import '../models/auth_state.dart';

/// Spec 16: username + password login.
abstract interface class AuthRepository {
  Stream<AuthState> watch();

  Future<AuthResult> signIn(String username, String password);

  Future<AuthResult> signUp(String username, String password);

  Future<void> createMerchant(String businessName);

  Future<void> signOut();
}
