import '../account_enums.dart';
import '../keep_result.dart';
import '../parser/parser_rule.dart';

/// What the developer lab needs (spec 06, rule 6). Screens never touch the channel themselves.
abstract interface class DevLabRepository {
  /// The rules file, parsed.
  Future<List<ParserRule>> parserRules();

  /// Runs the SAME filter and store as a real SMS (rows are marked simulated).
  Future<KeepResult> simulateIncoming(String sender, String body, SimSlot simSlot);
}
