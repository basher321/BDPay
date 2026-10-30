import '../core/validators.dart';
import 'account_enums.dart';
import 'models/wallet.dart';

/// Checks [candidate] (number already normalised) against the merchant's [existing] wallets.
/// The candidate's own id is ignored, so editing a wallet never clashes with itself.
/// - duplicate: another wallet (active or not) with the same operator and number (decision D9).
/// - simTaken: both active, same operator, same SIM, and the SIM is not unknown.
AddWalletResult checkWallet(List<Wallet> existing, Wallet candidate) {
  if (!isValidWalletNumber(candidate.operator, candidate.walletNumber)) return AddWalletResult.invalidNumber;
  final others = existing.where((w) => w.id != candidate.id && w.operator == candidate.operator);
  if (others.any((w) => w.walletNumber == candidate.walletNumber)) return AddWalletResult.duplicate;
  if (candidate.isActive &&
      candidate.simSlot != SimSlot.unknown &&
      others.any((w) => w.isActive && w.simSlot == candidate.simSlot)) {
    return AddWalletResult.simTaken;
  }
  return AddWalletResult.done;
}
