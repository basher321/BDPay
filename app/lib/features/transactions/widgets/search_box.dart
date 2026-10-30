import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../transactions_providers.dart';

/// Keeps its own controller, so rebuilds of the list never take focus or move the cursor.
class SearchBox extends ConsumerStatefulWidget {
  const SearchBox({super.key});

  @override
  ConsumerState<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends ConsumerState<SearchBox> {
  late final TextEditingController _controller = TextEditingController(text: ref.read(searchQueryProvider));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('searchBox'),
      controller: _controller,
      style: AppText.body13,
      decoration: InputDecoration(hintText: AppLocalizations.of(context).searchHint),
      onChanged: (q) => ref.read(searchQueryProvider.notifier).set(q),
    );
  }
}
