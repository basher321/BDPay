import 'package:flutter/material.dart';

import 'widgets/account_section.dart';
import 'widgets/connections_section.dart';
import 'widgets/developer_section.dart';
import 'widgets/device_section.dart';
import 'widgets/operators_section.dart';
import 'widgets/privacy_footer.dart';
import 'widgets/shopify_section.dart';
import 'widgets/wallets_section.dart';

/// The সেটিংস tab: the sections of spec 05 in order, in one scrolling list.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget gap(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 14), child: child);
    return ListView(
      key: const Key('settingsList'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        gap(const ConnectionsSection()),
        gap(const ShopifySection()),
        gap(const WalletsSection()),
        gap(const DeviceSection()),
        gap(const OperatorsSection()),
        gap(const DeveloperSection()),
        gap(const AccountSection()),
        const PrivacyFooter(),
      ],
    );
  }
}
