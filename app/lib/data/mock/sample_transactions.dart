import '../../domain/enums.dart';
import '../../domain/models/claim_info.dart';
import '../../domain/models/sms_transaction.dart';

/// The 5 sample items from spec 01. Times are relative to [now] (app start).
/// Raw SMS texts are copied from the reference file.
List<SmsTransaction> buildSampleTransactions(DateTime now) {
  DateTime ago(int minutes) => now.toUtc().subtract(Duration(minutes: minutes));
  return [
    SmsTransaction(
      id: '1',
      operator: MfsOperator.bkash,
      sender: 'bKash',
      trxId: '9K48X7Z2',
      amountPoisha: 125000,
      payerNumber: '01712345678',
      kind: TxKind.payment,
      verifyStatus: VerifyStatus.verified,
      syncStatus: SyncStatus.sent,
      receivedAt: ago(5),
      reference: 'ORD-101',
      balancePoisha: 1534050,
      serverCode: 200,
      serverMessage: 'অর্ডারের সাথে মিলেছে',
      rawBody: 'You have received payment Tk 1,250.00 from 01712345678. Ref: ORD-101. '
          'Fee Tk 0.00. Balance Tk 15,340.50. TrxID 9K48X7Z2 at 02/10/2026 18:25',
    ),
    SmsTransaction(
      id: '2',
      operator: MfsOperator.nagad,
      sender: 'NAGAD',
      trxId: '71B99AA2',
      amountPoisha: 250000,
      payerNumber: '01812345678',
      kind: TxKind.received,
      verifyStatus: VerifyStatus.verified,
      syncStatus: SyncStatus.sent,
      receivedAt: ago(35),
      serverCode: 200,
      rawBody: 'Money Received Amount: Tk 2,500.00 Sender: 01812345678 TxnID: 71B99AA2 '
          'Balance: Tk 15,000.00 Time: 02/10/2026 14:15',
    ),
    SmsTransaction(
      id: '3',
      operator: MfsOperator.rocket,
      sender: '16216',
      trxId: '24010200123',
      amountPoisha: 150000,
      payerNumber: '017123456789',
      kind: TxKind.received,
      verifyStatus: VerifyStatus.pending,
      syncStatus: SyncStatus.failed,
      receivedAt: ago(50),
      retryCount: 2,
      serverMessage: 'নেটওয়ার্ক সংযোগ নেই',
      rawBody: 'Tk1,500.00 received from 017123456789 for A/C: 019876543211. '
          'Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123',
    ),
    SmsTransaction(
      id: '4',
      operator: MfsOperator.upay,
      sender: 'upay',
      trxId: '4UP82910',
      amountPoisha: 80000,
      payerNumber: '01711223344',
      kind: TxKind.received,
      verifyStatus: VerifyStatus.pending,
      syncStatus: SyncStatus.queued,
      receivedAt: ago(95),
      rawBody: 'You have received Tk 800.00 from 01711223344. Txn ID: 4UP82910. '
          'Current balance Tk 3,400.00.',
    ),
    SmsTransaction(
      id: '5',
      operator: MfsOperator.bkash,
      sender: 'bKash',
      trxId: '8H22K9P1',
      amountPoisha: 43000,
      payerNumber: '01911002200',
      kind: TxKind.payment,
      verifyStatus: VerifyStatus.mismatch,
      syncStatus: SyncStatus.sent,
      receivedAt: ago(140),
      serverCode: 409,
      serverMessage: 'অর্ডারের টাকার সাথে মেলেনি',
      rawBody: 'You have received payment Tk 430.00 from 01911002200. TrxID 8H22K9P1',
      claim: const ClaimInfo(claimId: 'clm_demo_5', orderRef: '#1045', expectedAmountPoisha: 45000),
    ),
  ];
}
