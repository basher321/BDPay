import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/keep_result.dart';
import 'package:verifier/l10n/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('bn'));

  test('wire names match the Kotlin results and round-trip', () {
    expect(KeepResult.values.map((r) => r.toWire()),
        ['stored', 'duplicate', 'monitoringOff', 'senderNotTrusted', 'operatorOff', 'blocked', 'notIncoming']);
    for (final r in KeepResult.values) {
      expect(KeepResult.fromWire(r.toWire()), r);
    }
    expect(() => KeepResult.fromWire('foo'), throwsFormatException);
  });

  test('each result has its Bangla text from the spec', () {
    expect(KeepResult.stored.label(l), 'নেওয়া হয়েছে');
    expect(KeepResult.duplicate.label(l), 'আগেই নেওয়া হয়েছে (ডুপ্লিকেট)');
    expect(KeepResult.monitoringOff.label(l), 'মনিটরিং বন্ধ');
    expect(KeepResult.senderNotTrusted.label(l), 'প্রেরক বিশ্বস্ত নয় — নেওয়া হয়নি');
    expect(KeepResult.operatorOff.label(l), 'এই অপারেটর বন্ধ');
    expect(KeepResult.blocked.label(l), 'OTP/অফার — নেওয়া হয়নি');
    expect(KeepResult.notIncoming.label(l), 'টাকা গ্রহণের এসএমএস নয় — নেওয়া হয়নি');
  });
}
