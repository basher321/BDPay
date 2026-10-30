import 'package:intl/intl.dart';

final _thousands = NumberFormat('#,##0', 'en_US');

/// Formats whole poisha as taka for display: 125050 -> "৳ 1,250.50".
String formatPoisha(int poisha) {
  if (poisha < 0) {
    throw ArgumentError.value(poisha, 'poisha', 'must not be negative');
  }
  final taka = poisha ~/ 100;
  final rest = (poisha % 100).toString().padLeft(2, '0');
  return '৳ ${_thousands.format(taka)}.$rest';
}
