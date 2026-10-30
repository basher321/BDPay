import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/theme/app_theme.dart';

class MoneyText extends StatelessWidget {
  const MoneyText(this.poisha, {super.key, this.style = AppText.amount16});

  final int poisha;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(formatPoisha(poisha), style: style, maxLines: 1);
  }
}
