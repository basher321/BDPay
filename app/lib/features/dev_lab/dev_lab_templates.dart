import 'dart:ui';

import '../../core/theme/colors.dart';
import '../../domain/enums.dart';
import '../../l10n/app_localizations.dart';

/// Sample SMS for the developer lab. The sender and body are test data (SMS samples from the reference),
/// not UI text; the chip labels come from ARB.
enum LabTemplate {
  bkash(
    'bKash',
    'You have received payment Tk 1,250.00 from 01712345678. Ref: ORD-101. Fee Tk 0.00. Balance Tk 15,340.50. '
        'TrxID 9K48X7Z2 at 02/10/2026 18:25',
  ),
  nagad(
    'NAGAD',
    'Money Received Amount: Tk 2,500.00 Sender: 01812345678 TxnID: 71B99AA2 Balance: Tk 15,000.00 Time: 02/10/2026 14:15',
  ),
  rocket(
    '16216',
    'Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123',
  ),
  upay('upay', 'You have received Tk 800.00 from 01711223344. Txn ID: 4UP82910. Current balance Tk 3,400.00. Fee Tk 0.00.'),
  banglaBkash('bKash', 'আপনি 01712345678 থেকে Tk 1,250.00 পেয়েছেন। Ref: ORDER-99। ব্যালেন্স Tk 15,340.50। TrxID 9K48X7B5'),

  /// Trusted words from an untrusted number.
  fake(
    '01799999999',
    'You have received payment Tk 50,000.00 from 01712345678. Fee Tk 0.00. Balance Tk 65,340.50. TrxID FAKE1234',
  ),
  otp('bKash', 'Your bKash verification OTP is 482913. Do not share it with anyone.'),
  outgoing('bKash', 'Send Money Tk 500.00 to 01711000000 successful. TrxID ABC12345'),
  html('bKash', 'You have received Tk 100.00 from 01712345678. <img src=x onerror=alert(1)> TrxID HTML1234');

  const LabTemplate(this.sender, this.body);

  final String sender;
  final String body;

  String label(AppLocalizations l) => switch (this) {
        bkash => l.tplBkash,
        nagad => l.tplNagad,
        rocket => l.tplRocket,
        upay => l.tplUpay,
        banglaBkash => l.tplBanglaBkash,
        fake => l.tplFake,
        otp => l.tplOtp,
        outgoing => l.tplOutgoing,
        html => l.tplHtml,
      };

  /// Operator samples use the operator colour; the warning templates use amber.
  Color get color => switch (this) {
        bkash || banglaBkash => MfsOperator.bkash.textColor,
        nagad => MfsOperator.nagad.textColor,
        rocket => MfsOperator.rocket.textColor,
        upay => MfsOperator.upay.textColor,
        fake || otp || outgoing || html => AppColors.wa,
      };
}
