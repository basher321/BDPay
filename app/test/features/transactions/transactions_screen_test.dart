import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/theme/colors.dart';
import 'package:verifier/data/providers.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/review.dart';

import 'transactions_test_helpers.dart';

Color? chipColor(WidgetTester tester, String key) {
  final box = tester.widget<Container>(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(Container)).first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  testWidgets('list is newest first with the result count', (tester) async {
    await pumpAppAt(tester);
    expect(cardIds(tester), ['1', '2', '3', '4', '5']);
    expect(find.text('5 টি লেনদেন'), findsOneWidget);
  });

  testWidgets('typing in search keeps focus and cursor and narrows the list', (tester) async {
    await pumpAppAt(tester);
    final box = find.byKey(const Key('searchBox'));
    await tester.tap(box);
    for (final text in ['9', '9k', '9k48']) {
      await tester.enterText(box, text);
      await settle(tester);
      final field = tester.widget<TextField>(box);
      expect(field.focusNode?.hasFocus ?? tester.testTextInput.hasAnyClients, isTrue);
      expect(field.controller!.selection.baseOffset, text.length);
    }
    expect(cardIds(tester), ['1']);
    expect(find.text('1 টি লেনদেন'), findsOneWidget);
  });

  testWidgets('bKash, then bKash again returns to all 5; selected chip uses the bKash colour', (tester) async {
    await pumpAppAt(tester);
    await tester.tap(find.byKey(const Key('opChip-bkash')));
    await settle(tester);
    expect(cardIds(tester), ['1', '5']);
    expect(chipColor(tester, 'opChip-bkash'), AppColors.bkash.withValues(alpha: 0.2));
    await tester.tap(find.byKey(const Key('opChip-bkash')));
    await settle(tester);
    expect(cardIds(tester).length, 5);
    expect(chipColor(tester, 'opChip-bkash'), AppColors.sf);
  });

  testWidgets('review banner shows 1 mismatch; tapping it shows 1 item', (tester) async {
    await pumpAppAt(tester);
    expect(find.text('1 টি পেমেন্টে টাকা মেলেনি — দেখুন'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reviewBanner')));
    await settle(tester);
    expect(cardIds(tester), ['5']);
  });

  testWidgets('banner hidden when nothing is mismatch', (tester) async {
    final h = await pumpAppAt(tester);
    await h.transactions.review('5', ReviewDecision.approve, null);
    await settle(tester);
    expect(find.byKey(const Key('reviewBanner')), findsNothing);
  });

  testWidgets('status chips: {mismatch, rejected} shows two selected; a tap sets one; সব sets null', (tester) async {
    final h = await pumpAppAt(tester);
    final selected = AppColors.em.withValues(alpha: 0.2);
    h.container.read(transactionFilterProvider.notifier).set({VerifyStatus.mismatch, VerifyStatus.rejected});
    await settle(tester);
    expect(chipColor(tester, 'statusChip-mismatch'), selected);
    expect(chipColor(tester, 'statusChip-rejected'), selected);
    expect(chipColor(tester, 'statusChip-all'), AppColors.sf);

    await tester.tap(find.byKey(const Key('statusChip-verified')));
    await settle(tester);
    expect(h.container.read(transactionFilterProvider), {VerifyStatus.verified});
    expect(cardIds(tester), ['1', '2']);

    await tester.tap(find.byKey(const Key('statusChip-all')));
    await settle(tester);
    expect(h.container.read(transactionFilterProvider), isNull);
  });

  testWidgets('empty result shows the empty state', (tester) async {
    await pumpAppAt(tester);
    await tester.enterText(find.byKey(const Key('searchBox')), 'zzz');
    await settle(tester);
    expect(find.text('কিছু পাওয়া যায়নি'), findsOneWidget);
    expect(find.text('ফিল্টার বদলে আবার চেষ্টা করুন'), findsOneWidget);
  });

  testWidgets('filters and search stay set when switching tabs', (tester) async {
    await pumpAppAt(tester);
    await tester.enterText(find.byKey(const Key('searchBox')), '01');
    await tester.tap(find.byKey(const Key('opChip-bkash')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nav-transactions')));
    await settle(tester);
    expect(tester.widget<TextField>(find.byKey(const Key('searchBox'))).controller!.text, '01');
    expect(cardIds(tester), ['1', '5']);
  });

  testWidgets('operator and status chip rows scroll sideways', (tester) async {
    await pumpAppAt(tester);
    for (final key in ['operatorChips', 'statusChips']) {
      final view = tester.widget<SingleChildScrollView>(find.byKey(Key(key)));
      expect(view.scrollDirection, Axis.horizontal);
    }
  });
}
