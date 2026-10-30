import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/colors.dart';
import '../data/providers.dart';
import '../l10n/app_localizations.dart';
import 'app_tab.dart';

class AppBottomNav extends ConsumerWidget {
  const AppBottomNav({super.key, required this.tabs, required this.selected, required this.onSelect});

  final List<AppTab> tabs;
  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingCountProvider);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.sf,
        border: Border(top: BorderSide(color: AppColors.bd, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final tab in tabs)
              Expanded(
                child: NavItem(
                  key: ValueKey('nav-${tab.name}'),
                  tab: tab,
                  active: tab == selected,
                  badge: tab == AppTab.queue && pending > 0 ? pending : null,
                  onTap: () => onSelect(tab),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  const NavItem({super.key, required this.tab, required this.active, required this.onTap, this.badge});

  final AppTab tab;
  final bool active;
  final int? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 30,
                decoration: BoxDecoration(
                  color: active ? AppColors.em : null,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(tab.icon, size: 22, color: active ? AppColors.onEm : AppColors.t3),
              ),
              if (badge != null)
                Positioned(
                  top: -3,
                  right: 2,
                  child: Container(
                    key: const Key('queueBadge'),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(color: AppColors.wa, borderRadius: BorderRadius.circular(8)),
                    child: Text('$badge', style: AppText.navBadge),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tab.label(AppLocalizations.of(context)),
            style: active ? AppText.navActive : AppText.nav,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
