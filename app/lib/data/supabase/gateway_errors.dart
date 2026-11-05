import 'dart:async';
import 'dart:io';

/// Gateway failures in plain terms, so the repositories never see a Supabase type and can be tested with fakes.
/// None of them carries the server's message (it can contain the email); only a kind and a constraint name.

/// The network is down or the server did not answer in time.
class OfflineException implements Exception {
  const OfflineException();

  @override
  String toString() => 'OfflineException';
}

enum AuthFailure { badRequest, rateLimited, wrongPassword, userExists, weakPassword, notConfirmed, other }

class AuthGatewayException implements Exception {
  const AuthGatewayException(this.kind);

  final AuthFailure kind;

  @override
  String toString() => 'AuthGatewayException(${kind.name})';
}

enum TableFailure { uniqueViolation, checkViolation, denied, other }

class TableGatewayException implements Exception {
  const TableGatewayException(this.kind, {this.constraint});

  final TableFailure kind;

  /// The violated constraint or index name, when Postgres names one.
  final String? constraint;

  @override
  String toString() => 'TableGatewayException(${kind.name})';
}

/// True for the errors that mean "no connection". package:http's ClientException (thrown inside supabase_flutter)
/// is matched by its type name, so the app does not have to add package:http itself.
bool isOfflineError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HttpException ||
    e.runtimeType.toString() == 'ClientException';
