import 'dart:async';
import 'dart:convert';

import '../../domain/account_enums.dart';
import '../../domain/enums.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/claim_info.dart';
import '../../domain/models/sms_transaction.dart';
import '../../domain/parser/parse_sms.dart';
import '../../domain/parser/parser_rule.dart';
import '../../domain/repositories/device_health_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/review.dart';
import '../supabase/functions_gateway.dart';
import '../supabase/gateway_errors.dart';
import '../supabase/timers.dart';
import '../upload/mock_sms_uploader.dart';
import '../upload/native_sms_uploader.dart';
import '../upload/sms_uploader.dart';
import 'inbox_row.dart';
import 'sms_channel.dart';

/// Transactions from the phone's SMS store (sms_inbox), parsed with the rules file.
/// "sending" lives only in memory; the database holds queued, sent and failed.
///
/// Spec 13a ([nativeUploader] given = the real server): uploads run natively in the background (retry =
/// NativeSmsUploader.uploadNow, Dart writes no sync result), the claim and server id come from the row, review() calls claim-review, and
/// refreshNow() runs every 30 s while the app is in front ([inFront]).
class ChannelTransactionRepository implements TransactionRepository {
  ChannelTransactionRepository({
    required this._channel,
    required Future<List<ParserRule>> rules,
    required this._health,
    required this._settings,
    SmsUploader? uploader,
    this._nativeUploader,
    this._functions,
    this._timers = const RealTimers(),
    bool Function()? inFront,
  })  : _rulesFuture = rules,
        _inFront = inFront ?? (() => true) {
    _uploader = uploader ?? MockSmsUploader(isOnline: () => _online);
  }

  static const refreshEvery = Duration(seconds: 30);

  final NativeSmsUploader? _nativeUploader;
  final FunctionsGateway? _functions;
  final Timers _timers;
  final bool Function() _inFront;
  Cancelable? _refreshTimer;

  bool get _background => _nativeUploader != null;

  final SmsChannel _channel;
  final Future<List<ParserRule>> _rulesFuture;
  final DeviceHealthRepository _health;
  final SettingsRepository _settings;
  late final SmsUploader _uploader;

  final _changes = StreamController<List<SmsTransaction>>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  final _sending = <String>{};
  List<ParserRule> _rules = const [];
  List<SmsTransaction>? _current;
  Set<String>? _known;
  bool _online = true;
  bool _autoSend = true;
  bool? _autoSendPushed;
  Set<MfsOperator>? _pushedOperators;
  bool _started = false;

  /// The latest list (null until the first load).
  List<SmsTransaction>? get current => _current;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subs.add(_health.watch().listen((h) => _online = h.internetOnline));
    try {
      _rules = await _rulesFuture;
    } on Exception {
      _rules = const [];
    }
    await _syncOperatorsFromNative();
    _subs
      ..add(_settings.watch().listen(_onSettings))
      ..add(_channel.events.listen((e) {
        if (e == 'inbox') reload();
      }));
    if (_background) {
      _refreshTimer = _timers.periodic(refreshEvery, () {
        if (_inFront()) _channel.refreshNow().catchError((_) {});
      });
    }
    await reload();
  }

  void dispose() {
    _refreshTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
  }

  /// D12: once at start, the app's operator switches take the native (saved) set.
  Future<void> _syncOperatorsFromNative() async {
    try {
      final native = (await _channel.getHealth()).enabledOperators;
      final s = await _settings.watch().first;
      _pushedOperators = native;
      if (!_sameSet(s.enabledOperators, native)) await _settings.update(s.copyWith(enabledOperators: native));
    } on Exception {
      // Keep the app's settings; they are pushed on the next change.
    }
  }

  void _onSettings(AppSettings s) {
    if (_background && s.autoSend != _autoSendPushed) {
      _autoSendPushed = s.autoSend;
      _channel.setAutoSend(s.autoSend).catchError((_) {}); // plan 13a D151: the receiver obeys it while closed
    }
    _autoSend = s.autoSend;
    final ops = s.enabledOperators;
    final pushed = _pushedOperators;
    if (pushed == null || !_sameSet(pushed, ops)) {
      _pushedOperators = ops;
      _channel.setEnabledOperators(ops).catchError((_) {});
    }
  }

  static bool _sameSet<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

  /// Reads all rows and maps them. Rows that appear after the first load are new: with autoSend
  /// on, their queued ones are sent at once.
  Future<void> reload() async {
    List<InboxRow> rows;
    try {
      rows = await _channel.listInbox();
    } on Exception {
      return;
    }
    final list = [for (final r in rows) _map(r)];
    final known = _known;
    _known = {for (final t in list) t.id};
    _emit(list);
    if (known != null && _autoSend && !_background) {
      for (final t in list) {
        if (!known.contains(t.id) && t.syncStatus == SyncStatus.queued) unawaited(retry(t.id));
      }
    }
  }

  SmsTransaction _map(InboxRow r) {
    final p = parseSms(r.sender, r.body, _rules);
    final failed = !p.ok;
    return SmsTransaction(
      id: r.id,
      operator: MfsOperator.fromWire(r.operator),
      sender: r.sender,
      trxId: failed ? '—' : p.trxId!,
      amountPoisha: failed ? 0 : p.amountPoisha!,
      payerNumber: p.payerNumber,
      kind: p.kind,
      verifyStatus: VerifyStatus.fromWire(r.verifyStatus),
      syncStatus: _sending.contains(r.id) ? SyncStatus.sending : SyncStatus.fromWire(r.syncStatus),
      claim: _claim(r.claimJson),
      serverSmsId: r.serverSmsId,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(r.receivedAtMs, isUtc: true),
      rawBody: r.body,
      reference: p.reference,
      balancePoisha: p.balancePoisha,
      serverCode: r.serverCode,
      serverMessage: r.serverMessage,
      retryCount: r.retryCount,
      simSlot: SimSlot.fromWire(r.simSlot),
      parseFailed: failed,
    );
  }

  /// {claimId, orderRef, expectedAmountPoisha} or null; a malformed value is ignored.
  static ClaimInfo? _claim(String? json) {
    if (json == null) return null;
    try {
      final m = jsonDecode(json);
      if (m is! Map) return null;
      final id = m['claimId'], ref = m['orderRef'], amount = m['expectedAmountPoisha'];
      if (id is! String || ref is! String || amount is! int) return null;
      return ClaimInfo(claimId: id, orderRef: ref, expectedAmountPoisha: amount);
    } on FormatException {
      return null;
    }
  }

  void _emit(List<SmsTransaction> list) {
    _current = list;
    _changes.add(list);
  }

  void _setSending(String id, bool on) {
    on ? _sending.add(id) : _sending.remove(id);
    final c = _current;
    if (c == null) return;
    _emit([
      for (final t in c)
        t.id == id ? t.copyWith(syncStatus: on ? SyncStatus.sending : SyncStatus.queued) : t,
    ]);
  }

  SmsTransaction? _find(String id) {
    for (final t in _current ?? const <SmsTransaction>[]) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Stream<List<SmsTransaction>> watchAll() async* {
    final c = _current;
    if (c != null) yield c;
    yield* _changes.stream;
  }

  @override
  Future<void> retry(String id) async {
    final native = _nativeUploader;
    if (native != null) {
      // The native worker sends every waiting row; one upload runs at a time (spec 13a).
      await native.uploadNow();
      return;
    }
    final item = _find(id);
    if (item == null || !item.syncStatus.isPending || _sending.contains(id)) return;
    _setSending(id, true);
    try {
      final r = await _uploader.upload(item);
      await _channel.updateSync(
        id: id,
        syncStatus: r.syncStatus,
        verifyStatus: r.verifyStatus,
        retryCount: r.retryCount,
        serverCode: r.serverCode,
        serverMessage: r.serverMessage,
      );
      _sending.remove(id);
      await reload();
    } on Exception {
      _setSending(id, false);
    }
  }

  @override
  Future<void> retryAllPending() async {
    final native = _nativeUploader;
    if (native != null) return native.uploadNow();
    final ids = [for (final t in _current ?? const <SmsTransaction>[]) if (t.syncStatus.isPending) t.id];
    await Future.wait(ids.map(retry));
  }

  /// Spec 13a: the decision goes to the server (claim-review); the device never writes it (CLAUDE.md).
  /// No server id -> notAllowed; offline -> offline; done -> refreshNow() and done; anything else -> notAllowed.
  @override
  Future<ReviewResult> review(String id, ReviewDecision decision, String? note) async {
    final functions = _functions;
    final smsId = _find(id)?.serverSmsId;
    if (functions == null || smsId == null) return ReviewResult.notAllowed;
    final trimmed = note?.trim();
    final FunctionsReply r;
    try {
      r = await functions.call('claim-review', body: {
        'smsId': smsId,
        'decision': decision.toWire(),
        if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
      });
    } on OfflineException {
      return ReviewResult.offline;
    }
    if (r.ok && r.map['result'] == 'done') {
      await _channel.refreshNow().catchError((_) {});
      return ReviewResult.done;
    }
    return ReviewResult.notAllowed;
  }
}
