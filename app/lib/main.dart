import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'data/supabase/supabase_setup.dart';
import 'shell/not_configured_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig.fromDefines;
  if (!config.isComplete) {
    // Spec 13: one screen and nothing else.
    runApp(const NotConfiguredApp());
    return;
  }
  await initSupabase(config);
  runApp(const ProviderScope(child: BdpayApp()));
}
