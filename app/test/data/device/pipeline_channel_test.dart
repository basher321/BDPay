import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/device/device_health_repository.dart';
import 'package:verifier/data/device/device_transaction_repository.dart';
import 'package:verifier/data/device/sms_channel.dart';
import 'package:verifier/data/mock/mock_settings_repository.dart';
import 'package:verifier/data/upload/native_sms_uploader.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/parser/parser_rule.dart';
import 'package:verifier/domain/review.dart';

import '../supabase/fakes.dart';
import 'fake_native.dart';

const _rocket =
    'Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rulesJson = File('android/app/src/main/res/raw/parser_rules.json').readAsStringSync();

  late FakeNative native;
  late FakeFunctionsGateway fn;
  late FakeTimers timers;
  late ChannelDeviceHealthRepository health;
  late ChannelTransactionRepository repo;
  late MockSettingsRepository settings;
  var front = true;

  Future<void> start() async {
    final channel = SmsChannel();
    settings = MockSettingsRepository();
    health = ChannelDeviceHealthRepository(channel, listenLifecycle: false, serverMode: true)..start();
    repo = ChannelTransactionRepository(
      channel: channel,
      rules: Future.value(parseRules(rulesJson)),
      health: health,
      settings: settings,
      nativeUploader: NativeSmsUploader(channel),
      functions: fn,
      timers: timers,
      inFront: () => front,
    );
    await repo.start();
    await flush();
  }

  setUp(() {
    native = FakeNative()..rules = rulesJson;
    fn = FakeFunctionsGateway();
    timers = FakeTimers();
    front = true;
  });
  tearDown(() {
    repo.dispose();
    health.dispose();
    native.dispose();
  });

  test('listInbox maps server_sms_id, claim_json -> claim and "sending"', () async {
    native.rows
      ..add(FakeNative.row(
        id: 'a',
        sender: '16216',
        body: _rocket,
        operator: 'rocket',
        syncStatus: 'sent',
        verifyStatus: 'mismatch',
        serverSmsId: 'srv-1',
        claimJson: '{"claimId":"c1","orderRef":"#1045","expectedAmountPoisha":160000}',
      ))
      ..add(FakeNative.row(id: 'b', sender: '16216', body: _rocket, operator: 'rocket', syncStatus: 'sending'));
    await start();
    final list = repo.current!;
    final a = list.firstWhere((t) => t.id == 'a');
    expect(a.serverSmsId, 'srv-1');
    expect(a.claim?.orderRef, '#1045');
    expect(a.claim?.expectedAmountPoisha, 160000);
    expect(list.firstWhere((t) => t.id == 'b').syncStatus, SyncStatus.sending);
  });

  test('a malformed claim_json is ignored', () async {
    native.rows.add(FakeNative.row(id: 'a', sender: '16216', body: _rocket, operator: 'rocket', claimJson: '{oops'));
    await start();
    expect(repo.current!.single.claim, isNull);
  });

  test('retry / retryAllPending -> uploadNow; Dart writes no sync result', () async {
    native.rows.add(FakeNative.row(id: 'a', sender: '16216', body: _rocket, operator: 'rocket'));
    await start();
    await repo.retry('a');
    await repo.retryAllPending();
    expect(native.callsOf('uploadNow').length, 2);
    expect(native.callsOf('updateSync'), isEmpty);
  });

  test('autoSend is pushed to the native side (plan D151)', () async {
    await start();
    expect(native.callsOf('setAutoSend').map((c) => c.arguments), [true]);
    await settings.update(settings.current.copyWith(autoSend: false));
    await flush();
    expect(native.callsOf('setAutoSend').map((c) => c.arguments), [true, false]);
  });

  group('review mapping', () {
    setUp(() {
      native.rows
        ..add(FakeNative.row(id: 'up', sender: '16216', body: _rocket, operator: 'rocket', verifyStatus: 'mismatch', serverSmsId: 'srv-1'))
        ..add(FakeNative.row(id: 'local', sender: '16216', body: _rocket, operator: 'rocket', verifyStatus: 'mismatch'));
    });

    test('no server id -> notAllowed without a call', () async {
      await start();
      expect(await repo.review('local', ReviewDecision.approve, null), ReviewResult.notAllowed);
      expect(fn.calls, isEmpty);
    });

    test('done -> refreshNow() and done; the body has the server id, decision and note', () async {
      fn.answer('claim-review', reply(200, {'ok': true, 'result': 'done'}));
      await start();
      expect(await repo.review('up', ReviewDecision.reject, ' ভুল টাকা '), ReviewResult.done);
      expect(fn.calls.single.$3, {'smsId': 'srv-1', 'decision': 'reject', 'note': 'ভুল টাকা'});
      expect(native.callsOf('refreshNow'), isNotEmpty);
    });

    test('notAllowed and notFound -> notAllowed; offline -> offline', () async {
      fn.answer('claim-review', reply(200, {'ok': true, 'result': 'notAllowed'}));
      fn.answer('claim-review', reply(200, {'ok': true, 'result': 'notFound'}));
      fn.answer('claim-review', offline);
      await start();
      expect(await repo.review('up', ReviewDecision.approve, null), ReviewResult.notAllowed);
      expect(await repo.review('up', ReviewDecision.approve, null), ReviewResult.notAllowed);
      expect(await repo.review('up', ReviewDecision.approve, null), ReviewResult.offline);
    });
  });

  test('refreshNow every 30 s while the app is in front, not in the background', () async {
    await start();
    await timers.elapse(const Duration(seconds: 90));
    expect(native.callsOf('refreshNow').length, 3);
    front = false;
    await timers.elapse(const Duration(seconds: 90));
    expect(native.callsOf('refreshNow').length, 3);
  });

  test('health (server mode): pingServer = heartbeatNow; last contact and revoked come from the pipeline', () async {
    native.pipeline = {...native.pipeline, 'deviceId': 'd', 'lastServerContactMs': 1793253600000, 'revoked': false};
    await start();
    expect(health.current!.lastServerContactAt, DateTime.fromMillisecondsSinceEpoch(1793253600000, isUtc: true));
    expect(await health.pingServer(), isTrue);
    expect(native.callsOf('heartbeatNow').length, 1);
    native.pipeline = {...native.pipeline, 'revoked': true};
    native.send('pipeline');
    await flush();
    expect(health.current!.deviceRevoked, isTrue);
  });
}
