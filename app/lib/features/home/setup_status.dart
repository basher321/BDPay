import '../../domain/models/shopify_store.dart';
import '../../domain/models/wallet.dart';

/// What the "সেটআপ বাকি" card shows.
class SetupStatus {
  const SetupStatus({required this.hasActiveWallet, required this.hasStore});

  final bool hasActiveWallet;
  final bool hasStore;

  /// Shown when there is no active wallet OR no Shopify store.
  bool get show => !hasActiveWallet || !hasStore;
}

SetupStatus setupStatus(List<Wallet> wallets, ShopifyStore? store) =>
    SetupStatus(hasActiveWallet: wallets.any((w) => w.isActive), hasStore: store != null);
