import 'dart:async';

import '../../core/validators.dart';
import '../../domain/account_enums.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/models/wallet.dart';
import '../../domain/repositories/repository_errors.dart';
import '../../domain/repositories/wallet_repository.dart';
import 'app_foreground.dart';
import 'gateway_errors.dart';
import 'rows.dart';
import 'table_gateway.dart';
import 'value_stream.dart';

/// Spec 13: the wallets table (RLS limits it to the merchant). The app validates first; the database has the
/// final word. No delete. No network -> [OfflineError] and nothing changes.
class SupabaseWalletRepository implements WalletRepository {
  SupabaseWalletRepository({required this._tables, required Stream<AuthState> auth, this._foreground})
      : _authStream = auth;

  /// Constraint names from spec 12's migrations (plan 13 D139).
  static const numberUnique = 'wallets_operator_wallet_number_key';
  static const simUnique = 'wallets_active_sim_key';

  final TableGateway _tables;
  final Stream<AuthState> _authStream;
  final AppForeground? _foreground;
  final _wallets = ValueStream<List<Wallet>>(const []);
  final _subs = <StreamSubscription<void>>[];
  String? _merchantId;

  void start() {
    _subs.add(_authStream.listen((a) {
      final id = a.status == AuthStatus.signedIn ? a.merchant?.id : null;
      if (id == _merchantId) return;
      _merchantId = id;
      if (id == null) {
        _wallets.value = const [];
      } else {
        unawaited(refresh());
      }
    }));
    final fg = _foreground;
    if (fg != null) _subs.add(fg.resumed.listen((_) => unawaited(refresh())));
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _wallets.close();
  }

  @override
  Stream<List<Wallet>> watch() => _wallets.watch();

  /// Reads the merchant's wallets again. Errors keep the last list (the screen shows what it had).
  Future<void> refresh() async {
    final id = _merchantId;
    if (id == null) return;
    try {
      final rows = await _tables.listWallets(id);
      if (id == _merchantId) _wallets.value = List.unmodifiable(rows.map(walletFromRow));
    } on OfflineException {
      // keep
    } on TableGatewayException {
      // keep
    }
  }

  @override
  Future<AddWalletResult> add(Wallet w) async {
    final id = _merchantId;
    if (id == null) throw StateError('Not signed in');
    final number = normalizeWalletNumber(w.walletNumber);
    if (!isValidWalletNumber(w.operator, number)) return AddWalletResult.invalidNumber;
    final clean = w.copyWith(walletNumber: number);
    return _write(() => _tables.insertWallet(walletInsertRow(id, Wallet(
          id: '',
          operator: clean.operator,
          walletNumber: clean.walletNumber,
          accountType: clean.accountType,
          label: _label(clean.label),
          simSlot: clean.simSlot,
          isActive: clean.isActive,
        ))));
  }

  /// Operator, number and isActive do not change here (spec 05 rule 7).
  @override
  Future<AddWalletResult> update(Wallet w) => _write(() => _tables.updateWallet(w.id, {
        'account_type': w.accountType.toWire(),
        'label': _label(w.label),
        'sim_slot': w.simSlot.toWire(),
      }));

  @override
  Future<AddWalletResult> setActive(String id, bool on) => _write(() => _tables.updateWallet(id, {'is_active': on}));

  Future<AddWalletResult> _write(Future<Object?> Function() call) async {
    try {
      await call();
    } on TableGatewayException catch (x) {
      return switch (x.kind) {
        TableFailure.uniqueViolation => x.constraint == simUnique ? AddWalletResult.simTaken : AddWalletResult.duplicate,
        TableFailure.checkViolation => AddWalletResult.invalidNumber,
        TableFailure.denied || TableFailure.other => throw x,
      };
    } on OfflineException {
      throw const OfflineError();
    }
    await refresh();
    return AddWalletResult.done;
  }

  static String? _label(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}
