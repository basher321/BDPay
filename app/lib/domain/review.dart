/// The merchant's manual decision on a mismatch payment.
enum ReviewDecision {
  approve,
  reject;

  String toWire() => name;

  static ReviewDecision fromWire(String wire) {
    for (final v in values) {
      if (v.name == wire) return v;
    }
    throw FormatException('Unknown ReviewDecision: "$wire"');
  }
}

enum ReviewResult { done, offline, notAllowed }
