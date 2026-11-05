import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/app_info.dart';

void main() {
  test('appVersion equals the pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(appVersion, match!.group(1));
  });
}
