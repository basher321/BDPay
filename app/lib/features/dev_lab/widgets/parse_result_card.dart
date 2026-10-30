import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../domain/parser/parse_sms.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/operator_badge.dart';

extension ParseErrorLabel on ParseError {
  String label(AppLocalizations l) => switch (this) {
        ParseError.unknownSender => l.parseErrUnknownSender,
        ParseError.noTrxId => l.parseErrNoTrxId,
        ParseError.noAmount => l.parseErrNoAmount,
      };
}

/// The parseSms result, like the reference "পার্সিং ফলাফল" card. Every value is plain Text (SMS text is untrusted).
class ParseResultCard extends StatelessWidget {
  const ParseResultCard({super.key, required this.parsed});

  final ParsedSms parsed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = parsed;
    final okColor = p.ok ? AppColors.ok : AppColors.er;
    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [Expanded(child: Text(label, style: AppText.mu12)), Flexible(child: value)]),
        );
    Widget text(String? v, Key key, {TextStyle? style}) => Text(
          v ?? l.labNotFound,
          key: key,
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: v == null ? AppText.body13.copyWith(color: AppColors.t3) : (style ?? AppText.body13),
        );
    return AppCard(
      key: const Key('parseResult'),
      big: true,
      surface: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(l.labResultTitle, style: AppText.title14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: okColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(p.ok ? l.labValid : l.labInvalid, style: AppText.chip.copyWith(color: okColor)),
            ),
          ]),
          const Divider(color: AppColors.bd, height: 20),
          row(l.labOperator, p.operator == null ? text(null, const Key('parseOperator')) : Align(alignment: Alignment.centerRight, child: OperatorBadge(p.operator!))),
          row(l.labTrxId, text(p.trxId, const Key('parseTrxId'), style: AppText.title13.copyWith(color: AppColors.em))),
          row(l.labAmount, text(p.amountPoisha == null ? null : formatPoisha(p.amountPoisha!), const Key('parseAmount'))),
          row(l.labPayer, text(p.payerNumber, const Key('parsePayer'))),
          if (p.errors.isNotEmpty)
            row(
              l.labErrors,
              Text(
                p.errors.map((e) => e.label(l)).join(', '),
                key: const Key('parseErrors'),
                textAlign: TextAlign.end,
                style: AppText.body13.copyWith(color: AppColors.er),
              ),
            ),
        ],
      ),
    );
  }
}
