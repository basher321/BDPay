import 'package:supabase_flutter/supabase_flutter.dart';

import 'gateway_errors.dart';

/// An Edge Function's answer. [json] is the decoded body (or null). Never logged.
class FunctionsReply {
  const FunctionsReply(this.status, this.json);

  final int status;
  final Object? json;

  bool get ok => status >= 200 && status < 300;

  Map<String, dynamic> get map => json is Map<String, dynamic> ? json as Map<String, dynamic> : const {};
}

/// Calls an Edge Function with the signed-in user's token (supabase_flutter adds it).
abstract interface class FunctionsGateway {
  /// Any HTTP status comes back as a reply; no network -> [OfflineException].
  Future<FunctionsReply> call(String name, {bool get = false, Map<String, dynamic>? body});
}

class SupabaseFunctionsGateway implements FunctionsGateway {
  SupabaseFunctionsGateway(this._functions, {this.timeout = const Duration(seconds: 15)});

  final FunctionsClient _functions;
  final Duration timeout;

  @override
  Future<FunctionsReply> call(String name, {bool get = false, Map<String, dynamic>? body}) async {
    try {
      final r = await _functions
          .invoke(name, method: get ? HttpMethod.get : HttpMethod.post, body: get ? null : (body ?? const {}))
          .timeout(timeout);
      return FunctionsReply(r.status, r.data);
    } on FunctionException catch (e) {
      return FunctionsReply(e.status, e.details);
    } catch (e) {
      if (isOfflineError(e)) throw const OfflineException();
      rethrow;
    }
  }
}
