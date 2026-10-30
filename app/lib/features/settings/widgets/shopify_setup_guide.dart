import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../l10n/app_localizations.dart';

/// Spec 13 rule 5: the collapsible "সেটআপ গাইড" (steps from shopify_app/MERCHANT_SETUP_BN.txt), shown when connected.
class ShopifySetupGuide extends StatefulWidget {
  const ShopifySetupGuide({super.key});

  @override
  State<ShopifySetupGuide> createState() => _ShopifySetupGuideState();
}

class _ShopifySetupGuideState extends State<ShopifySetupGuide> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final steps = [
      l.shopifyGuideStep1,
      l.shopifyGuideStep2,
      l.shopifyGuideStep3,
      l.shopifyGuideStep4,
      l.shopifyGuideStep5,
    ];
    return Column(
      key: const Key('shopifyGuide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          key: const Key('shopifyGuideToggle'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(l.shopifyGuideTitle, style: AppText.title13)),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20, color: AppColors.t3),
              ],
            ),
          ),
        ),
        if (_open)
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 20, child: Text('${i + 1}.', style: AppText.sm.copyWith(color: AppColors.em))),
                  Expanded(child: Text(steps[i], key: Key('shopifyGuideStep$i'), style: AppText.sm)),
                ],
              ),
            ),
      ],
    );
  }
}
