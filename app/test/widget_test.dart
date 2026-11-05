import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/shell/app_bottom_nav.dart';

import 'test_helpers.dart';

Future<void> _setDevMode(WidgetTester tester, TestMocks mocks, bool on) async {
  await mocks.settings.update(mocks.settings.current.copyWith(developerMode: on));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows 4 tabs in order when developer mode is off', (tester) async {
    await pumpApp(tester);
    expect(find.byType(NavItem), findsNWidgets(4));
    expect(find.text('হোম'), findsWidgets);
    final order = tester.widgetList<NavItem>(find.byType(NavItem)).map((n) => n.tab.name).toList();
    expect(order, ['home', 'transactions', 'queue', 'settings']);
  });

  testWidgets('shows 5 tabs with পরীক্ষা before সেটিংস when developer mode is on', (tester) async {
    final mocks = await pumpApp(tester);
    await _setDevMode(tester, mocks, true);
    expect(find.byType(NavItem), findsNWidgets(5));
    final order = tester.widgetList<NavItem>(find.byType(NavItem)).map((n) => n.tab.name).toList();
    expect(order, ['home', 'transactions', 'queue', 'devLab', 'settings']);
  });

  testWidgets('turning developer mode off on পরীক্ষা returns to হোম', (tester) async {
    final mocks = await pumpApp(tester);
    await _setDevMode(tester, mocks, true);
    await tester.tap(find.byKey(const ValueKey('nav-devLab')));
    await tester.pump();
    expect(tester.widget<NavItem>(find.byKey(const ValueKey('nav-devLab'))).active, isTrue);
    await _setDevMode(tester, mocks, false);
    expect(find.byKey(const ValueKey('nav-devLab')), findsNothing);
    expect(tester.widget<NavItem>(find.byKey(const ValueKey('nav-home'))).active, isTrue);
  });

  testWidgets('পাঠানো বাকি badge shows 2 with the sample data and hides at 0', (tester) async {
    final mocks = await pumpApp(tester);
    final badge = find.byKey(const Key('queueBadge'));
    expect(badge, findsOneWidget);
    expect(find.descendant(of: badge, matching: find.text('2')), findsOneWidget);

    final done = mocks.transactions.retryAllPending();
    await tester.pump(const Duration(milliseconds: 800));
    await done;
    await tester.pump();
    expect(badge, findsNothing);
  });

  testWidgets('online pill changes when setOnline(false) is called', (tester) async {
    final mocks = await pumpApp(tester);
    expect(find.text('অনলাইন'), findsOneWidget);
    await mocks.health.setOnline(false);
    await tester.pump();
    await tester.pump();
    expect(find.text('অফলাইন'), findsOneWidget);
    expect(find.text('অনলাইন'), findsNothing);
  });
}
