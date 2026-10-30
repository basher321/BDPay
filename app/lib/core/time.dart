import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// Asia/Dhaka is a fixed UTC+6 with no daylight saving.
const dhakaOffset = Duration(hours: 6);

/// The Dhaka wall-clock time, kept in a UTC DateTime so its fields read as Dhaka time.
DateTime toDhakaWall(DateTime time) => time.toUtc().add(dhakaOffset);

/// "hh:mm AM/PM" in Asia/Dhaka.
String dhakaClock(DateTime utc) => DateFormat('hh:mm a', 'en_US').format(toDhakaWall(utc));

/// "এইমাত্র", "N মিনিট আগে", "N ঘণ্টা আগে" or "N দিন আগে".
String timeAgo(DateTime utc, DateTime now, [AppLocalizations? l10n]) {
  final l = l10n ?? lookupAppLocalizations(const Locale('bn'));
  final diff = now.difference(utc);
  if (diff.inSeconds < 60) return l.justNow;
  if (diff.inMinutes < 60) return l.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l.hoursAgo(diff.inHours);
  return l.daysAgo(diff.inDays);
}
