import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/enums.dart';

import '../../test_helpers.dart';

/// The emulator scenario from spec 04, run in the full app: offline, then back online ->
/// the queue empties by itself and the toast shows. Proves the shell starts the coordinator.
void main() {
  testWidgets('internet back -> queue empties by itself and the toast shows', (tester) async {
    final mocks = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('nav-queue')));
    await tester.pump();
    await tester.pump();
    expect(find.text('পাঠানো বাকি (2)'), findsOneWidget);

    await mocks.health.setOnline(false);
    await tester.pump();
    await tester.pump();
    await mocks.health.setOnline(true);
    await tester.pump();
    await tester.pump();
    // The coordinator started a send: both items are sending now.
    expect(mocks.transactions.current.where((t) => t.syncStatus == SyncStatus.sending).length, 2);

    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    await tester.pump();
    expect(find.text('সব পাঠানো হয়েছে!'), findsOneWidget);
    expect(find.text('ইন্টারনেট ফিরেছে — 2 টি পাঠানো হয়েছে'), findsOneWidget);
    expect(find.byKey(const Key('queueBadge')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('autoSend off -> nothing is sent when the internet comes back', (tester) async {
    final mocks = await pumpApp(tester);
    await mocks.settings.update(mocks.settings.current.copyWith(autoSend: false));
    await tester.pump();
    await mocks.health.setOnline(false);
    await tester.pump();
    await tester.pump();
    await mocks.health.setOnline(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(mocks.transactions.current.where((t) => t.syncStatus.isPending).length, 2);
  });
}
