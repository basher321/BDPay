import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/shell/app_tab.dart';
import 'package:verifier/widgets/app_button.dart';

import '../transactions/transactions_test_helpers.dart';

export '../transactions/transactions_test_helpers.dart';

/// Pumps the whole app on the পাঠানো বাকি tab (fixed clock, fresh mocks, optional custom items).
Future<AppHarness> pumpQueue(WidgetTester tester, {List<dynamic>? items}) =>
    pumpAppAt(tester, tab: AppTab.queue, items: items?.cast());

AppButton buttonByKey(WidgetTester tester, String key) => tester.widget<AppButton>(find.byKey(Key(key)));

Color? textColor(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).style?.color;

/// Lets the 700 ms mock send finish and the list stream deliver.
Future<void> finishSend(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 750));
  await tester.pump();
  await tester.pump();
}
