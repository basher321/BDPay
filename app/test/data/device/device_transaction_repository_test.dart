import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/device/device_health_repository.dart';
import 'package:verifier/data/device/device_transaction_repository.dart';
import 'package:verifier/data/device/sms_channel.dart';
import 'package:verifier/data/mock/mock_settings_repository.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/parser/parser_rule.dart';
import 'package:verifier/domain/review.dart';

import 'fake_native.dart';

const rocketBody =
    'Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rulesJson = File('android/app/src/main/res/raw/parser_rules.json').readAsStringSync();

  late FakeNative native;
  late MockSettingsRepository settings;
  late ChannelDeviceHealthRepository health;
  late ChannelTransactionRepository repo;

  Future<void> start({bool autoSend = true}) async {
    final channel = SmsChannel();
    settings = MockSettingsRepository();
    await settings.update(settings.current.copyWith(autoSend: autoSend));
    health = ChannelDeviceHealthRepository(channel, listenLifecycle: false)..start();
    repo = ChannelTransactionRepository(
      channel: channel,
      rules: Future.value(parseRules(rulesJson)),
      health: health,
      settings: settings,
    );
    await repo.start();
    await flush();
  }

  setUp(() {
    native = FakeNative()..rules = rulesJson;
  });
  tearDown(() {
    repo.dispose();
    health.dispose();
    native.dispose();
  });

  test('rows become transactions: parsed fields, UTC time, SIM slot, newest first', () async {
    native.rows
      ..add(FakeNative.row(id: 'a', sender: '16216', body: rocketBody, operator: 'rocket', simSlot: 'sim2', receivedAtMs: 1000))
      ..add(FakeNative.row(id: 'b', sender: 'bKash', body: 'You have received Tk 5.00 from 01712345678. TrxID ABC12345', receivedAtMs: 2000, simSlot: 'unknown'));
    await start();
    final list = repo.current!;
    expect(list.map((t) => t.id), ['b', 'a']);
    final r = list[1];
    expect(r.operator, MfsOperator.rocket);
    expect(r.trxId, '24010200123');
    expect(r.amountPoisha, 150000);
    expect(r.payerNumber, '017123456789');
    expect(r.simSlot, SimSlot.sim2);
    expect(r.receivedAt, DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true));
    expect(r.receivedAt.isUtc, isTrue);
    expect(r.parseFailed, isFalse);
    expect(list[0].simSlot, SimSlot.unknown);
  });

  test('a row that does not parse is still shown and queued: trxId "—", amount 0, parseFailed', () async {
    native.rows.add(FakeNative.row(id: 'x', sender: 'bKash', body: 'You have received money from a friend'));
    await start(autoSend: false);
    final t = repo.current!.single;
    expect(t.parseFailed, isTrue);
    expect(t.trxId, '—');
    expect(t.amountPoisha, 0);
    expect(t.syncStatus, SyncStatus.queued);
  });

  test('an "inbox" event reloads the list', () async {
    await start(autoSend: false);
    expect(repo.current, isEmpty);
    native.rows.add(FakeNative.row(id: 'n', sender: '16216', body: rocketBody, operator: 'rocket'));
    native.send('inbox');
    await flush();
    expect(repo.current!.single.id, 'n');
  });

  test('autoSend on: a new row is sent at once; sending is never written; verify stays pending (D13)', () async {
    await start();
    native.rows.add(FakeNative.row(id: 'n', sender: '16216', body: rocketBody, operator: 'rocket'));
    native.send('inbox');
    await flush();
    expect(repo.current!.single.syncStatus, SyncStatus.sending);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await flush();
    final updates = native.callsOf('updateSync');
    expect(updates, hasLength(1));
    final a = updates.single.arguments as Map;
    expect(a['syncStatus'], 'sent');
    expect(a['verifyStatus'], 'pending');
    expect(a['serverCode'], 200);
    expect(repo.current!.single.syncStatus, SyncStatus.sent);
  });

  test('autoSend off: a new row stays queued', () async {
    await start(autoSend: false);
    native.rows.add(FakeNative.row(id: 'n', sender: '16216', body: rocketBody, operator: 'rocket'));
    native.send('inbox');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await flush();
    expect(native.callsOf('updateSync'), isEmpty);
    expect(repo.current!.single.syncStatus, SyncStatus.queued);
  });

  test('rows already there at start are not auto-sent', () async {
    native.rows.add(FakeNative.row(id: 'old', sender: '16216', body: rocketBody, operator: 'rocket'));
    await start();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(native.callsOf('updateSync'), isEmpty);
  });

  test('retry offline -> failed with one more retry', () async {
    native.rows.add(FakeNative.row(id: 'r', sender: '16216', body: rocketBody, operator: 'rocket', retryCount: 2));
    await start(autoSend: false);
    await health.setOnline(false);
    await flush();
    await repo.retry('r');
    await flush();
    final a = native.callsOf('updateSync').single.arguments as Map;
    expect(a['syncStatus'], 'failed');
    expect(a['retryCount'], 3);
    expect(repo.current!.single.syncStatus, SyncStatus.failed);
  });

  test('review is never decided on the device', () async {
    await start(autoSend: false);
    final calls = native.calls.length;
    expect(await repo.review('x', ReviewDecision.approve, null), ReviewResult.notAllowed);
    expect(native.calls.length, calls);
  });

  test('D12: start copies the native operator set into the app settings; later changes go to native', () async {
    native.health = {...native.health, 'enabledOperators': ['bkash', 'nagad', 'rocket']};
    await start(autoSend: false);
    expect(settings.current.enabledOperators, {MfsOperator.bkash, MfsOperator.nagad, MfsOperator.rocket});
    expect(native.callsOf('setEnabledOperators'), isEmpty);
    await settings.update(settings.current.copyWith(enabledOperators: {MfsOperator.bkash}));
    await flush();
    expect(native.callsOf('setEnabledOperators').single.arguments, ['bkash']);
  });
}
