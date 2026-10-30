import '../../core/validators.dart';
import '../../domain/account_enums.dart';
import '../../domain/models/wallet.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../../domain/wallet_rules.dart';
import 'mock_account_data.dart';

/// MOCK - replaced in spec 13: the server checks and stores wallets.
class MockWalletRepository implements WalletRepository {
  MockWalletRepository(this._data);

  final MockAccountData _data;

  @override
  Stream<List<Wallet>> watch() =>
      _data.revision.watch().map((_) => List.unmodifiable(_data.current?.wallets ?? const <Wallet>[]));

  MockMerchantData get _account {
    final a = _data.current;
    if (a == null) throw StateError('Not signed in');
    return a;
  }

  @override
  Future<AddWalletResult> add(Wallet w) async {
    final account = _account;
    final candidate = _clean(w, id: '', walletNumber: normalizeWalletNumber(w.walletNumber), isActive: w.isActive);
    final result = checkWallet(account.wallets, candidate);
    if (result != AddWalletResult.done) return result;
    account.wallets = [...account.wallets, _clean(candidate, id: _data.newId('w'))];
    _data.changed();
    return result;
  }

  /// Operator, number and isActive cannot change here.
  @override
  Future<AddWalletResult> update(Wallet w) async {
    final account = _account;
    final old = account.wallets.firstWhere((x) => x.id == w.id);
    final candidate = Wallet(
      id: old.id,
      operator: old.operator,
      walletNumber: old.walletNumber,
      accountType: w.accountType,
      label: _label(w.label),
      simSlot: w.simSlot,
      isActive: old.isActive,
    );
    final result = checkWallet(account.wallets, candidate);
    if (result != AddWalletResult.done) return result;
    _replace(account, candidate);
    return result;
  }

  @override
  Future<AddWalletResult> setActive(String id, bool on) async {
    final account = _account;
    final candidate = account.wallets.firstWhere((x) => x.id == id).copyWith(isActive: on);
    final result = checkWallet(account.wallets, candidate);
    if (result != AddWalletResult.done) return result;
    _replace(account, candidate);
    return result;
  }

  void _replace(MockMerchantData account, Wallet w) {
    account.wallets = [for (final x in account.wallets) x.id == w.id ? w : x];
    _data.changed();
  }

  static String? _label(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  static Wallet _clean(Wallet w, {required String id, String? walletNumber, bool? isActive}) => Wallet(
        id: id,
        operator: w.operator,
        walletNumber: walletNumber ?? w.walletNumber,
        accountType: w.accountType,
        label: _label(w.label),
        simSlot: w.simSlot,
        isActive: isActive ?? w.isActive,
      );
}
