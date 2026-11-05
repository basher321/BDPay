import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/l10n/app_localizations.dart';
import 'package:verifier/widgets/app_button.dart';
import 'package:verifier/widgets/empty_state.dart';

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('bn'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('EmptyState renders an icon, a title and a hint', (tester) async {
    await tester.pumpWidget(_wrap(const EmptyState(icon: '⏳', title: 'Title', hint: 'Hint')));
    expect(find.text('⏳'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Hint'), findsOneWidget);
  });

  testWidgets('a long button label is cut with an ellipsis in a narrow row', (tester) async {
    await tester.pumpWidget(_wrap(SizedBox(
      width: 80,
      child: Row(children: [Expanded(child: AppButton.primary(label: 'X' * 200, onPressed: () {}))]),
    )));
    expect(tester.takeException(), isNull);
  });
}
