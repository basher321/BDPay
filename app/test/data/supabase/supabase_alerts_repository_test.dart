import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/supabase/supabase_alerts_repository.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/models/auth_state.dart';
import 'package:verifier/domain/models/merchant.dart';

import 'fakes.dart';

const _signedIn = AuthState(
  status: AuthStatus.signedIn,
  email: 'a@b.co',
  merchant: Merchant(id: 'm-1', businessName: 'দোকান'),
);

Map<String, Object?> _alert(String id, String openedAt) => {
      'id': id,
      'kind': 'phoneSilent',
      'openedAt': openedAt,
      'title': 'যাচাই ফোন অফলাইন — পেমেন্ট নিশ্চিত হচ্ছে না',
      'hint': 'ফোন চালু ও চার্জে রাখুন',
    };

void main() {
  late FakeFunctionsGateway fn;
  late FakeTimers timers;
  late FakeForeground fg;
  late StreamController<AuthState> auth;
  late SupabaseAlertsRepository repo;

  setUp(() {
    fn = FakeFunctionsGateway();
    timers = FakeTimers();
    fg = FakeForeground();
    auth = StreamController<AuthState>.broadcast();
    repo = SupabaseAlertsRepository(functions: fn, auth: auth.stream, timers: timers, foreground: fg)..start();
  });

  Future<void> signIn() async {
    auth.add(_signedIn);
    await pumpEventQueue();
  }

  test('refresh after sign-in, sorted newest first, malformed entries skipped', () async {
    fn.answer('alerts-list', reply(200, {
      'ok': true,
      'alerts': [
        _alert('old', '2026-10-30T05:00:00Z'),
        {'id': 'broken'},
        _alert('new', '2026-10-30T06:00:00Z'),
      ],
    }));
    await signIn();
    final list = await repo.watch().first;
    expect(list.map((a) => a.id), ['new', 'old']);
    expect(list.first.openedAt.isUtc, isTrue);
    expect(list.first.title, 'যাচাই ফোন অফলাইন — পেমেন্ট নিশ্চিত হচ্ছে না');
    expect(fn.calls.single.$2, isTrue, reason: 'GET');
  });

  test('refresh when the app comes to the front and every 5 minutes', () async {
    fn.answer('alerts-list', reply(200, {'ok': true, 'alerts': <Object>[]}));
    await signIn();
    expect(fn.count('alerts-list'), 1);
    fg.resume();
    await pumpEventQueue();
    expect(fn.count('alerts-list'), 2);
    await timers.elapse(const Duration(minutes: 10));
    expect(fn.count('alerts-list'), 4);
  });

  test('errors keep the last list; nothing is fetched when signed out', () async {
    fn.answer('alerts-list', reply(200, {'ok': true, 'alerts': [_alert('a', '2026-10-30T05:00:00Z')]}));
    fn.answer('alerts-list', offline);
    await signIn();
    await repo.refresh();
    expect((await repo.watch().first).single.id, 'a');
    auth.add(AuthState.signedOut);
    await pumpEventQueue();
    final calls = fn.count('alerts-list');
    expect(await repo.watch().first, isEmpty);
    await timers.elapse(const Duration(minutes: 10));
    await repo.refresh();
    expect(fn.count('alerts-list'), calls);
  });
}
