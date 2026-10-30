import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../core/time.dart';
import '../../../l10n/app_localizations.dart';

/// The SMS amount against the order amount, always positive:
/// SMS lower -> "৳ 20.00 কম", SMS higher -> "... বেশি", equal -> "৳ 0.00".
String amountDifference(int expectedPoisha, int smsPoisha, [AppLocalizations? l10n]) {
  final l = l10n ?? lookupAppLocalizations(const Locale('bn'));
  final diff = smsPoisha - expectedPoisha;
  final amount = formatPoisha(diff.abs());
  if (diff < 0) return l.differenceLess(amount);
  if (diff > 0) return l.differenceMore(amount);
  return amount;
}

/// Full date and time in Asia/Dhaka, e.g. "29 Oct 2026, 06:25 PM".
String dhakaDateTime(DateTime utc) => DateFormat('dd MMM yyyy, hh:mm a', 'en_US').format(toDhakaWall(utc));
