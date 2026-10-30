import '../../domain/account_enums.dart';
import '../../domain/keep_result.dart';
import '../../domain/parser/parser_rule.dart';
import '../../domain/repositories/dev_lab_repository.dart';
import 'sms_channel.dart';

class ChannelDevLabRepository implements DevLabRepository {
  ChannelDevLabRepository(this._channel, this._rules);

  final SmsChannel _channel;
  final Future<List<ParserRule>> _rules;

  @override
  Future<List<ParserRule>> parserRules() => _rules;

  @override
  Future<KeepResult> simulateIncoming(String sender, String body, SimSlot simSlot) =>
      _channel.simulateIncoming(sender, body, simSlot);
}
