import 'dart:async';

import 'package:flutter_test/flutter_test.dart' show pumpEventQueue;
import 'package:verifier/data/supabase/app_foreground.dart';
import 'package:verifier/data/supabase/auth_gateway.dart';
import 'package:verifier/data/supabase/functions_gateway.dart';
import 'package:verifier/data/supabase/gateway_errors.dart';
import 'package:verifier/data/supabase/table_gateway.dart';
import 'package:verifier/data/supabase/timers.dart';
import 'package:verifier/data/supabase/url_opener.dart';

/// Fake gateways for the spec 13 repository tests. Each records its calls and can be told to fail.

class FakeAuthGateway implements AuthGateway {
  String? userId;
  String? email;
  Object? signInError;
  Object? signUpError;
  final signIns = <(String, String)>[];
  final signUps = <(String, String)>[];
  int signOuts = 0;
  final _changes = StreamController<void>.broadcast();

  @override
  String? get currentUserId => userId;

  @override
  String? get currentEmail => email;

  @override
  Stream<void> get changes => _changes.stream;

  void emitChange() => _changes.add(null);

  @override
  Future<void> signIn(String email, String password) async {
    signIns.add((email, password));
    if (signInError != null) throw signInError!;
    userId = 'user-1';
    this.email = email;
  }

  @override
  Future<void> signUp(String email, String password) async {
    signUps.add((email, password));
    if (signUpError != null) throw signUpError!;
    userId = 'user-1';
    this.email = email;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    userId = null;
    email = null;
  }
}

class FakeTableGateway implements TableGateway {
  /// userId -> merchant row.
  final merchants = <String, Row>{};
  final wallets = <Row>[];
  Object? nextError;
  int listCalls = 0;
  int _ids = 0;

  void _maybeFail() {
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
  }

  @override
  Future<Row?> merchantForUser(String userId) async {
    _maybeFail();
    return merchants[userId];
  }

  @override
  Future<Row> insertMerchant(String ownerId, String businessName) async {
    _maybeFail();
    if (merchants.containsKey(ownerId)) {
      throw const TableGatewayException(TableFailure.uniqueViolation, constraint: 'merchants_owner_id_key');
    }
    return merchants[ownerId] = {'id': 'm-${++_ids}', 'business_name': businessName};
  }

  @override
  Future<List<Row>> listWallets(String merchantId) async {
    listCalls++;
    _maybeFail();
    return [for (final w in wallets) if (w['merchant_id'] == merchantId) _public(w)];
  }

  @override
  Future<Row> insertWallet(Row row) async {
    _maybeFail();
    final w = {...row, 'id': 'w-${++_ids}'};
    wallets.add(w);
    return _public(w);
  }

  @override
  Future<Row> updateWallet(String id, Row fields) async {
    _maybeFail();
    final w = wallets.firstWhere((x) => x['id'] == id);
    w.addAll(fields);
    return _public(w);
  }

  static Row _public(Row w) => {for (final e in w.entries) if (e.key != 'merchant_id') e.key: e.value};
}

class FakeFunctionsGateway implements FunctionsGateway {
  /// name -> answers, used in order; the last one repeats.
  final answers = <String, List<Object>>{};
  final calls = <(String, bool, Map<String, dynamic>?)>[];

  void answer(String name, Object replyOrError) => answers.putIfAbsent(name, () => []).add(replyOrError);

  int count(String name) => calls.where((c) => c.$1 == name).length;

  @override
  Future<FunctionsReply> call(String name, {bool get = false, Map<String, dynamic>? body}) async {
    calls.add((name, get, body));
    final list = answers[name];
    if (list == null || list.isEmpty) throw StateError('no fake answer for $name');
    final a = list.length > 1 ? list.removeAt(0) : list.first;
    if (a is FunctionsReply) return a;
    throw a;
  }
}

class FakeUrlOpener implements UrlOpener {
  bool result = true;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return result;
  }
}

class FakeForeground implements AppForeground {
  final _c = StreamController<void>.broadcast();

  @override
  Stream<void> get resumed => _c.stream;

  void resume() => _c.add(null);
}

/// A fake clock with periodic timers that fire as time is moved forward.
class FakeTimers implements Timers {
  FakeTimers([DateTime? start]) : _now = start ?? DateTime.utc(2026, 10, 30, 6);

  DateTime _now;
  final _timers = <_FakeTimer>[];

  @override
  DateTime now() => _now;

  @override
  Cancelable periodic(Duration every, void Function() tick) {
    final t = _FakeTimer(every, tick, _now.add(every));
    _timers.add(t);
    return t;
  }

  int get active => _timers.where((t) => !t.cancelled).length;

  /// Moves time forward by [d], firing every due tick in order. Lets async work run between ticks.
  Future<void> elapse(Duration d) async {
    final end = _now.add(d);
    while (true) {
      final due = _timers.where((t) => !t.cancelled && !t.next.isAfter(end)).toList()
        ..sort((a, b) => a.next.compareTo(b.next));
      if (due.isEmpty) break;
      final t = due.first;
      _now = t.next;
      t.next = t.next.add(t.every);
      t.tick();
      await pumpEventQueue();
    }
    _now = end;
    await pumpEventQueue();
  }
}

class _FakeTimer implements Cancelable {
  _FakeTimer(this.every, this.tick, this.next);

  final Duration every;
  final void Function() tick;
  DateTime next;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;
}

FunctionsReply reply(int status, [Object? json]) => FunctionsReply(status, json);

const offline = OfflineException();
