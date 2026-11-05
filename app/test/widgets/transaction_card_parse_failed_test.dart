import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/theme/app_theme.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/sms_transaction.dart';
import 'package:verifier/l10n/app_localizations.dart';
import 'package:verifier/widgets/transaction_card.dart';

void main() {
  testWidgets('a parse-failed row shows "অজানা ফরম্যাট" instead of the TrxID and ৳ 0.00', (tester) async {
    final t = SmsTransaction(
      id: 'x',
      operator: MfsOperator.bkash,
      sender: 'bKash',
      trxId: '—',
      amountPoisha: 0,
      kind: TxKind.received,
      verifyStatus: VerifyStatus.pending,
      syncStatus: SyncStatus.queued,
      receivedAt: DateTime.utc(2026, 10, 29, 6),
      rawBody: 'You have received money',
      parseFailed: true,
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('bn'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: TransactionCard(transaction: t)),
    ));
    await tester.pump();
    expect(find.text('অজানা ফরম্যাট'), findsOneWidget);
    expect(find.textContaining('—'), findsWidgets);
    expect(find.text('৳ 0.00'), findsOneWidget);
  });
}
