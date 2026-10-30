import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// DEV / DEMO ONLY - never used by release builds (they start from main.dart).
/// Starts the app without a server: the mock repositories are used (login demo@bdpay.test, code 123456), while
/// the native SMS capture on the phone is real.
/// Run: flutter run -t lib/main_dev.dart    Build: flutter build apk --debug -t lib/main_dev.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: BdpayApp()));
}
