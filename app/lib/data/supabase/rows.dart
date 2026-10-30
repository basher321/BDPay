import '../../domain/account_enums.dart';
import '../../domain/enums.dart';
import '../../domain/models/app_alert.dart';
import '../../domain/models/merchant.dart';
import '../../domain/models/wallet.dart';
import 'table_gateway.dart';

/// snake_case rows <-> app records. Wire values go through the enums' fromWire, so bad server data fails loudly.

Merchant merchantFromRow(Row r) => Merchant(id: r['id'] as String, businessName: r['business_name'] as String);

Wallet walletFromRow(Row r) => Wallet(
      id: r['id'] as String,
      operator: MfsOperator.fromWire(r['operator'] as String),
      walletNumber: r['wallet_number'] as String,
      accountType: AccountType.fromWire(r['account_type'] as String),
      label: r['label'] as String?,
      simSlot: SimSlot.fromWire(r['sim_slot'] as String),
      isActive: r['is_active'] as bool,
    );

/// A new wallet row. id and the times are set by the database.
Row walletInsertRow(String merchantId, Wallet w) => {
      'merchant_id': merchantId,
      'operator': w.operator.toWire(),
      'wallet_number': w.walletNumber,
      'account_type': w.accountType.toWire(),
      'label': w.label,
      'sim_slot': w.simSlot.toWire(),
      'is_active': w.isActive,
    };

/// One alerts-list entry, or null when it is not a well-formed alert (it is then skipped).
AppAlert? alertFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'], kind = j['kind'], opened = j['openedAt'], title = j['title'], hint = j['hint'];
  if (id is! String || kind is! String || opened is! String || title is! String || hint is! String) return null;
  final at = DateTime.tryParse(opened);
  if (at == null) return null;
  return AppAlert(id: id, kind: kind, openedAt: at.toUtc(), title: title, hint: hint);
}
