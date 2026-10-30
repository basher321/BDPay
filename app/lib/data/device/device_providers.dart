import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/parser/parser_rule.dart';
import '../../domain/repositories/dev_lab_repository.dart';
import 'device_dev_lab_repository.dart';
import 'sms_channel.dart';

/// The native SMS channel (spec 06). Tests never use it: they override the repositories.
final smsChannelProvider = Provider<SmsChannel>((ref) => SmsChannel());

/// The rules file from the native side (the only copy).
/// Spec 13a: read again when the native side reports downloaded rules ("rules" event).
final parserRulesProvider = FutureProvider<List<ParserRule>>((ref) async {
  final channel = ref.watch(smsChannelProvider);
  final sub = channel.events.where((e) => e == 'rules').listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return parseRules(await channel.getParserRules());
});

final devLabRepositoryProvider = Provider<DevLabRepository>(
  (ref) => ChannelDevLabRepository(ref.watch(smsChannelProvider), ref.watch(parserRulesProvider.future)),
);
