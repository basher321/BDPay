import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/device/sms_channel.dart';

/// A fake Kotlin side for the "bdpay/sms" channels: rows, health and a call log.
class FakeNative {
  FakeNative() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(SmsChannel.methodName), _handle);
    messenger.setMockStreamHandler(
      const EventChannel(SmsChannel.eventName),
      MockStreamHandler.inline(onListen: (_, sink) => _sink = sink, onCancel: (_) => _sink = null),
    );
  }

  final rows = <Map<String, Object?>>[];
  final calls = <MethodCall>[];
  Map<String, Object?> health = {
    'smsPermission': true,
    'batteryOptimizationOff': false,
    'internetOnline': true,
    'maker': 'google',
    'monitoring': true,
    'enabledOperators': ['bkash', 'nagad', 'rocket', 'upay'],
    'autoStartConfirmed': false,
  };
  String rules = '[]';
  MockStreamHandlerEventSink? _sink;

  // Spec 13a pipeline state and answers.
  Map<String, Object?> pipeline = {
    'deviceId': null,
    'revoked': false,
    'clockOffsetMs': 0,
    'rulesVersion': 1,
    'lastServerContactMs': null,
  };
  bool heartbeatResult = true;
  bool deactivateResult = true;

  void dispose() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(SmsChannel.methodName), null);
    messenger.setMockStreamHandler(const EventChannel(SmsChannel.eventName), null);
  }

  void send(String event) => _sink?.success(event);

  List<MethodCall> callsOf(String method) => calls.where((c) => c.method == method).toList();

  static Map<String, Object?> row({
    required String id,
    required String sender,
    required String body,
    int receivedAtMs = 1793253600000,
    String simSlot = 'sim1',
    String syncStatus = 'queued',
    String verifyStatus = 'pending',
    int retryCount = 0,
    String operator = 'bkash',
    String source = 'sms',
    String? serverSmsId,
    String? claimJson,
  }) =>
      {
        'id': id,
        'sender': sender,
        'body': body,
        'received_at_ms': receivedAtMs,
        'sim_slot': simSlot,
        'sync_status': syncStatus,
        'verify_status': verifyStatus,
        'retry_count': retryCount,
        'server_code': null,
        'server_message': null,
        'created_at_ms': receivedAtMs,
        'operator': operator,
        'source': source,
        'server_sms_id': serverSmsId,
        'claim_json': claimJson,
      };

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'getParserRules':
        return rules;
      case 'listInbox':
        final sorted = [...rows]..sort((a, b) => (b['received_at_ms']! as int).compareTo(a['received_at_ms']! as int));
        return sorted;
      case 'getHealth':
        return health;
      case 'updateSync':
        final a = call.arguments as Map;
        final r = rows.firstWhere((x) => x['id'] == a['id']);
        r['sync_status'] = a['syncStatus'];
        r['verify_status'] = a['verifyStatus'];
        r['retry_count'] = a['retryCount'];
        r['server_code'] = a['serverCode'];
        r['server_message'] = a['serverMessage'];
        return null;
      case 'requestSmsPermission':
        health = {...health, 'smsPermission': true};
        return true;
      case 'setMonitoring':
        health = {...health, 'monitoring': call.arguments};
        return null;
      case 'setAutoStartConfirmed':
        health = {...health, 'autoStartConfirmed': call.arguments};
        return null;
      case 'getInstallId':
        return 'install-1';
      case 'getDevicePublicKey':
        return 'PUBLIC-SPKI';
      case 'getPipelineState':
        return pipeline;
      case 'heartbeatNow':
        return heartbeatResult;
      case 'deactivateDevice':
        return deactivateResult;
      case 'setDeviceConfig':
        final a = call.arguments as Map;
        pipeline = {...pipeline, 'deviceId': a['deviceId'], 'revoked': false};
        return null;
      case 'clearDeviceConfig':
        pipeline = {...pipeline, 'deviceId': null, 'revoked': false};
        return null;
      default:
        return null;
    }
  }
}

/// Lets channel replies and stream events arrive.
Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
