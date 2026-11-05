import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/theme/app_theme.dart';
import 'package:verifier/data/device/device_providers.dart';
import 'package:verifier/data/mock/mock_dev_lab_repository.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/keep_result.dart';
import 'package:verifier/domain/parser/parse_sms.dart';
import 'package:verifier/domain/parser/parser_rule.dart';
import 'package:verifier/features/dev_lab/dev_lab_screen.dart';
import 'package:verifier/l10n/app_localizations.dart';

/// Stands in for the native filter: same order and the same rules file (the real one runs in Kotlin tests).
MockDevLabRepository fakeLab(List<ParserRule> rules) {
  final stored = <String>{};
  return MockDevLabRepository(rules, decide: (sender, body, _) {
    final rule = ruleForSender(rules, sender);
    if (rule == null) return KeepResult.senderNotTrusted;
    final text = normalizeSmsBody(body);
    if (rule.ignore.hasMatch(text)) return KeepResult.blocked;
    if (!rule.incoming.hasMatch(text)) return KeepResult.notIncoming;
    return stored.add('${normalizeSender(sender)}|$body') ? KeepResult.stored : KeepResult.duplicate;
  });
}

Future<MockDevLabRepository> pumpLab(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rules = parseRules(File('android/app/src/main/res/raw/parser_rules.json').readAsStringSync());
  final lab = fakeLab(rules);
  await tester.pumpWidget(ProviderScope(
    overrides: [devLabRepositoryProvider.overrideWithValue(lab)],
    child: MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('bn'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const Scaffold(body: DevLabScreen()),
    ),
  ));
  await tester.pump();
  return lab;
}

Future<void> inject(WidgetTester tester, String template) async {
  await tester.tap(find.byKey(Key('tpl-$template')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('labInject')));
  await tester.pump();
  await tester.pump();
}

String resultText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('labKeepResult'))).data!;

void main() {
  testWidgets('info card and all template chips', (tester) async {
    await pumpLab(tester);
    expect(find.text('এসএমএস পরীক্ষা (ডেভেলপার)'), findsOneWidget);
    expect(find.text('আসল টাকা ছাড়াই পার্সিং, ভুয়া এসএমএস ঠেকানো ও ডুপ্লিকেট চেক পরীক্ষা করুন।'), findsOneWidget);
    for (final label in [
      'bKash পেমেন্ট প্রাপ্তি',
      'Nagad টাকা প্রাপ্তি',
      'Rocket টাকা প্রাপ্তি',
      'Upay পেমেন্ট',
      'বাংলা bKash মেসেজ',
      '⚠ ভুয়া এসএমএস',
      '⚠ OTP',
      '⚠ টাকা পাঠানো (outgoing)',
      '⚠ HTML ইনজেকশন',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('সিম ১'), findsOneWidget);
    expect(find.text('জানি না'), findsOneWidget);
  });

  testWidgets('"⚠ ভুয়া এসএমএস" -> "প্রেরক বিশ্বস্ত নয় — নেওয়া হয়নি"', (tester) async {
    await pumpLab(tester);
    await inject(tester, 'fake');
    expect(resultText(tester), 'প্রেরক বিশ্বস্ত নয় — নেওয়া হয়নি');
  });

  testWidgets('"⚠ OTP" -> "OTP/অফার — নেওয়া হয়নি"', (tester) async {
    await pumpLab(tester);
    await inject(tester, 'otp');
    expect(resultText(tester), 'OTP/অফার — নেওয়া হয়নি');
  });

  testWidgets('"⚠ টাকা পাঠানো (outgoing)" -> "টাকা গ্রহণের এসএমএস নয় — নেওয়া হয়নি"', (tester) async {
    await pumpLab(tester);
    await inject(tester, 'outgoing');
    expect(resultText(tester), 'টাকা গ্রহণের এসএমএস নয় — নেওয়া হয়নি');
  });

  testWidgets('"⚠ HTML ইনজেকশন" is stored with the exact text; again -> duplicate', (tester) async {
    final lab = await pumpLab(tester);
    await tester.tap(find.byKey(const Key('labSim-sim2')));
    await inject(tester, 'html');
    expect(resultText(tester), 'নেওয়া হয়েছে');
    final call = lab.calls.single;
    expect(call.$1, 'bKash');
    expect(call.$2, contains('<img src=x onerror=alert(1)>'));
    expect(call.$3, SimSlot.sim2);
    await tester.tap(find.byKey(const Key('labInject')));
    await tester.pump();
    await tester.pump();
    expect(resultText(tester), 'আগেই নেওয়া হয়েছে (ডুপ্লিকেট)');
  });

  testWidgets('"পার্স করে দেখুন" shows operator, TrxID, amount and payer', (tester) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('labParse')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('parseResult')), findsOneWidget);
    expect(find.text('ভ্যালিড এমএফএস'), findsOneWidget);
    expect(find.text('bKash'), findsWidgets);
    expect(tester.widget<Text>(find.byKey(const Key('parseTrxId'))).data, '9K48X7Z2');
    expect(tester.widget<Text>(find.byKey(const Key('parseAmount'))).data, '৳ 1,250.00');
    expect(tester.widget<Text>(find.byKey(const Key('parsePayer'))).data, '01712345678');
  });

  testWidgets('a text without TrxID shows the error', (tester) async {
    await pumpLab(tester);
    await tester.enterText(find.byKey(const Key('labBody')), 'You have received Tk 100.00 from 01712345678.');
    await tester.tap(find.byKey(const Key('labParse')));
    await tester.pump();
    await tester.pump();
    expect(find.text('অকার্যকর'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('parseErrors'))).data, 'TrxID পাওয়া যায়নি');
    expect(tester.widget<Text>(find.byKey(const Key('parseTrxId'))).data, 'পাওয়া যায়নি');
  });

  testWidgets('the HTML body is shown as plain text in the field and the result card', (tester) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('tpl-html')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('labParse')));
    await tester.pump();
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('labBody')));
    expect(field.controller!.text, contains('<img src=x onerror=alert(1)>'));
    expect(tester.widget<Text>(find.byKey(const Key('parseTrxId'))).data, 'HTML1234');
  });

  testWidgets('the text fields do not feed the keyboard\'s learning', (tester) async {
    await pumpLab(tester);
    for (final key in ['labSender', 'labBody']) {
      final f = tester.widget<TextField>(find.byKey(Key(key)));
      expect(f.enableIMEPersonalizedLearning, isFalse, reason: key);
      expect(f.enableSuggestions, isFalse, reason: key);
      expect(f.autocorrect, isFalse, reason: key);
    }
  });
}
