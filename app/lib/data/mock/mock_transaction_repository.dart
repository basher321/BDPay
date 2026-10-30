import '../../domain/enums.dart';
import '../../domain/models/sms_transaction.dart';
import '../../domain/repositories/device_health_repository.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/review.dart';
import '../upload/mock_sms_uploader.dart';
import 'mock_store.dart';

class MockTransactionRepository implements TransactionRepository {
  MockTransactionRepository(DeviceHealthRepository health, List<SmsTransaction> initial)
      : _store = MockStore(_sorted(initial)) {
    health.watch().listen((h) => _online = h.internetOnline);
  }

  final MockStore<List<SmsTransaction>> _store;
  bool _online = true;

  /// The current list, for tests.
  List<SmsTransaction> get current => _store.value;

  static List<SmsTransaction> _sorted(List<SmsTransaction> list) =>
      [...list]..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  @override
  Stream<List<SmsTransaction>> watchAll() => _store.watch();

  void _replace(String id, SmsTransaction Function(SmsTransaction) change) {
    _store.value = [for (final t in _store.value) t.id == id ? change(t) : t];
  }

  SmsTransaction? _find(String id) {
    for (final t in _store.value) {
      if (t.id == id) return t;
    }
    return null;
  }

  // MOCK - replaced by the server in spec 13. The send itself lives in MockSmsUploader (spec 06).
  late final _uploader = MockSmsUploader(isOnline: () => _online, markVerified: true);

  @override
  Future<void> retry(String id) async {
    final item = _find(id);
    if (item == null || !item.syncStatus.isPending) return;
    _replace(id, (t) => t.copyWith(syncStatus: SyncStatus.sending));
    final result = await _uploader.upload(_find(id)!);
    _replace(id, result.applyTo);
  }

  @override
  Future<void> retryAllPending() async {
    final ids = [for (final t in _store.value) if (t.syncStatus.isPending) t.id];
    await Future.wait(ids.map(retry));
  }

  // MOCK - replaced by the server in spec 13
  @override
  Future<ReviewResult> review(String id, ReviewDecision decision, String? note) async {
    final item = _find(id);
    if (item == null || item.verifyStatus != VerifyStatus.mismatch) return ReviewResult.notAllowed;
    if (!_online) return ReviewResult.offline;
    _replace(
      id,
      (t) => switch (decision) {
        ReviewDecision.approve => t.copyWith(verifyStatus: VerifyStatus.verified, serverMessage: 'ম্যানুয়ালি অনুমোদিত'),
        ReviewDecision.reject => t.copyWith(verifyStatus: VerifyStatus.rejected, serverMessage: 'ম্যানুয়ালি বাতিল'),
      },
    );
    return ReviewResult.done;
  }
}
