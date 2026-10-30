import '../../domain/models/sms_transaction.dart';
import '../../domain/models/wallet.dart';
import '../queue/queue_logic.dart';

/// True when [id] is the only active wallet, so turning it off leaves none.
bool isLastActiveWallet(List<Wallet> wallets, String id) {
  final active = wallets.where((w) => w.isActive).toList();
  return active.length == 1 && active.first.id == id;
}

/// Queue items (queued, sending or failed) that block logout.
int logoutBlockedCount(List<SmsTransaction> all) => queueItems(all).length;
