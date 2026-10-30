import '../../domain/account_enums.dart';
import '../../domain/keep_result.dart';
import '../../domain/parser/parser_rule.dart';
import '../../domain/repositories/dev_lab_repository.dart';

/// For tests: rules from the given list, keep results from [decide].
class MockDevLabRepository implements DevLabRepository {
  MockDevLabRepository(this.rules, {required this.decide});

  final List<ParserRule> rules;
  final KeepResult Function(String sender, String body, SimSlot sim) decide;
  final calls = <(String, String, SimSlot)>[];

  @override
  Future<List<ParserRule>> parserRules() async => rules;

  @override
  Future<KeepResult> simulateIncoming(String sender, String body, SimSlot simSlot) async {
    calls.add((sender, body, simSlot));
    return decide(sender, body, simSlot);
  }
}
