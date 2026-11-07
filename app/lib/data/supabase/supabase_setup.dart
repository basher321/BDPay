import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../core/app_config.dart';
import '../../domain/models/auth_state.dart';
import 'app_foreground.dart';
import 'auth_gateway.dart';
import 'functions_gateway.dart';
import 'secure_session_storage.dart';
import 'supabase_alerts_repository.dart';
import 'supabase_connections_repository.dart';
import 'supabase_auth_repository.dart';
import 'supabase_store_repository.dart';
import 'supabase_wallet_repository.dart';
import 'table_gateway.dart';
import 'url_opener.dart';

/// Starts Supabase once, before the app runs. debug: false so no request or auth event is logged; the session
/// is kept in secure storage (plan D140).
Future<void> initSupabase(AppConfig config) => Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.anonKey,
      authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
      debug: false,
    );

SupabaseClient get _client => Supabase.instance.client;

FunctionsGateway buildFunctionsGateway() => SupabaseFunctionsGateway(_client.functions);

SupabaseAuthRepository buildAuthRepository() =>
    SupabaseAuthRepository(auth: SupabaseAuthGateway(_client.auth), tables: SupabaseTableGateway(_client));

SupabaseWalletRepository buildWalletRepository(Stream<AuthState> auth, AppForeground foreground) =>
    SupabaseWalletRepository(tables: SupabaseTableGateway(_client), auth: auth, foreground: foreground);

SupabaseStoreRepository buildStoreRepository(Stream<AuthState> auth, AppForeground foreground) =>
    SupabaseStoreRepository(
      functions: SupabaseFunctionsGateway(_client.functions),
      opener: const UrlLauncherOpener(),
      auth: auth,
      foreground: foreground,
    );

/// Spec 17.
SupabaseConnectionsRepository buildConnectionsRepository(Stream<AuthState> auth, AppForeground foreground) =>
    SupabaseConnectionsRepository(functions: SupabaseFunctionsGateway(_client.functions), auth: auth, foreground: foreground);

SupabaseAlertsRepository buildAlertsRepository(Stream<AuthState> auth, AppForeground foreground) =>
    SupabaseAlertsRepository(functions: SupabaseFunctionsGateway(_client.functions), auth: auth, foreground: foreground);
