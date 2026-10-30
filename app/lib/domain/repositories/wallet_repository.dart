import '../account_enums.dart';
import '../models/wallet.dart';

/// The signed-in merchant's wallets. There is no delete.
abstract interface class WalletRepository {
  Stream<List<Wallet>> watch();

  Future<AddWalletResult> add(Wallet w);

  Future<AddWalletResult> update(Wallet w);

  /// done, or simTaken when turning on would clash with another active wallet (decision D7).
  Future<AddWalletResult> setActive(String id, bool on);
}
