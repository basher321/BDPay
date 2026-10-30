import 'package:supabase_flutter/supabase_flutter.dart';

import 'gateway_errors.dart';

typedef Row = Map<String, dynamic>;

/// Merchants and wallets only (spec 13). RLS limits every call to the signed-in owner's merchant.
abstract interface class TableGateway {
  /// {id, business_name} or null.
  Future<Row?> merchantForUser(String userId);

  Future<Row> insertMerchant(String ownerId, String businessName);

  Future<List<Row>> listWallets(String merchantId);

  Future<Row> insertWallet(Row row);

  Future<Row> updateWallet(String id, Row fields);
}

const _merchantColumns = 'id, business_name';
const walletColumns = 'id, operator, wallet_number, account_type, label, sim_slot, is_active';

class SupabaseTableGateway implements TableGateway {
  SupabaseTableGateway(this._db);

  final SupabaseClient _db;

  @override
  Future<Row?> merchantForUser(String userId) =>
      _guard(() => _db.from('merchants').select(_merchantColumns).eq('owner_id', userId).maybeSingle());

  @override
  Future<Row> insertMerchant(String ownerId, String businessName) => _guard(
        () => _db
            .from('merchants')
            .insert({'owner_id': ownerId, 'business_name': businessName})
            .select(_merchantColumns)
            .single(),
      );

  @override
  Future<List<Row>> listWallets(String merchantId) => _guard(
        () => _db.from('wallets').select(walletColumns).eq('merchant_id', merchantId).order('created_at'),
      );

  @override
  Future<Row> insertWallet(Row row) =>
      _guard(() => _db.from('wallets').insert(row).select(walletColumns).single());

  @override
  Future<Row> updateWallet(String id, Row fields) =>
      _guard(() => _db.from('wallets').update(fields).eq('id', id).select(walletColumns).single());

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      throw tableErrorOf(e.code, e.message);
    } catch (e) {
      if (isOfflineError(e)) throw const OfflineException();
      rethrow;
    }
  }
}

final _constraintName = RegExp(r'constraint "([^"]+)"');

/// Postgres error code (+ the constraint name in its message) -> [TableGatewayException]. The message itself is
/// not kept.
TableGatewayException tableErrorOf(String? code, String message) {
  final constraint = _constraintName.firstMatch(message)?.group(1);
  return switch (code) {
    '23505' => TableGatewayException(TableFailure.uniqueViolation, constraint: constraint),
    '23514' => TableGatewayException(TableFailure.checkViolation, constraint: constraint),
    '42501' => const TableGatewayException(TableFailure.denied),
    _ => const TableGatewayException(TableFailure.other),
  };
}
