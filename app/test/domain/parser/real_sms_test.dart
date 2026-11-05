import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/parser/parse_sms.dart';
import 'package:verifier/domain/parser/parser_rule.dart';

/// Spec 14: every real SMS sample in tests/real_sms/ (repo root) parses to its expected fields. Dart only parses
/// (the phone's keep/drop filter is Kotlin), so only "keep" samples are checked here (plan 14 D189).
/// Failure messages name the file and the field, never the SMS text or values.
void main() {
  final rules = parseRules(File('android/app/src/main/res/raw/parser_rules.json').readAsStringSync());
  final dir = Directory('../tests/real_sms');
  final files = dir.existsSync() ? (dir.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path))) : <File>[];
  String name(File f) => f.uri.pathSegments.last;

  test('tests/real_sms holds only .sms + .expected.json pairs (${files.length} files)', () {
    final names = files.map(name).toSet();
    final bad = [
      for (final n in names)
        if (n.endsWith('.sms')) ...[if (!names.contains('${n.substring(0, n.length - 4)}.expected.json')) n]
        else if (n.endsWith('.expected.json')) ...[if (!names.contains('${n.substring(0, n.length - 14)}.sms')) n]
        else n,
    ];
    expect(bad, isEmpty, reason: 'unpaired or unknown files');
  });

  for (final f in files.where((f) => name(f).endsWith('.sms'))) {
    final id = name(f).substring(0, name(f).length - 4);
    test('real sample $id', () {
      final expectedFile = File('${dir.path}/$id.expected.json');
      if (!expectedFile.existsSync()) fail('$id: no expected file');
      final exp = jsonDecode(expectedFile.readAsStringSync()) as Map<String, dynamic>;
      if (exp['keep'] != true) return; // drop samples: checked by the Kotlin and Deno suites
      final text = f.readAsStringSync().replaceAll('\r\n', '\n');
      final cut = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
      final nl = cut.indexOf('\n');
      if (nl < 0) fail('$id: no body line');
      final p = parseSms(cut.substring(0, nl), cut.substring(nl + 1), rules);
      expect(p.ok, isTrue, reason: '$id: does not parse');
      expect(p.operator?.name == exp['operator'], isTrue, reason: '$id: operator differs');
      expect(p.trxId == exp['trxId'], isTrue, reason: '$id: trxId differs');
      expect(p.amountPoisha == exp['amountPoisha'], isTrue, reason: '$id: amountPoisha differs');
      expect(p.payerNumber == exp['payerNumber'], isTrue, reason: '$id: payerNumber differs');
      expect(p.kind.name == exp['kind'], isTrue, reason: '$id: kind differs');
    });
  }
}
