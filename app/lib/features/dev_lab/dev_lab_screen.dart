import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/account_providers.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../data/device/device_providers.dart';
import '../../domain/account_enums.dart';
import '../../domain/keep_result.dart';
import '../../domain/parser/parse_sms.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import 'dev_lab_templates.dart';
import 'widgets/parse_result_card.dart';

/// The পরীক্ষা tab (spec 06, rule 6): try parsing and the keep rule without real money.
/// "⚡ অ্যাপে পাঠান" runs the same native filter and store as a real SMS.
class DevLabScreen extends ConsumerStatefulWidget {
  const DevLabScreen({super.key});

  @override
  ConsumerState<DevLabScreen> createState() => _DevLabScreenState();
}

class _DevLabScreenState extends ConsumerState<DevLabScreen> {
  final _sender = TextEditingController(text: LabTemplate.bkash.sender);
  final _body = TextEditingController(text: LabTemplate.bkash.body);
  LabTemplate? _template = LabTemplate.bkash;
  SimSlot _sim = SimSlot.sim1;
  ParsedSms? _parsed;
  KeepResult? _result;
  bool _busy = false;

  @override
  void dispose() {
    _sender.dispose();
    _body.dispose();
    super.dispose();
  }

  void _pick(LabTemplate t) => setState(() {
        _template = t;
        _sender.text = t.sender;
        _body.text = t.body;
        _parsed = null;
        _result = null;
      });

  Future<void> _parse() async {
    final rules = await ref.read(devLabRepositoryProvider).parserRules();
    if (!mounted) return;
    setState(() => _parsed = parseSms(_sender.text, _body.text, rules));
  }

  Future<void> _inject() async {
    if (_busy) return;
    setState(() => _busy = true);
    KeepResult? result;
    try {
      result = await ref.read(devLabRepositoryProvider).simulateIncoming(_sender.text, _body.text, _sim);
    } on Exception {
      result = null;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final result = _result;
    final kept = result == KeepResult.stored || result == KeepResult.duplicate;
    final rulesVersion = ref.watch(pipelineStateProvider).value?.rulesVersion;
    return ListView(
      key: const Key('devLabList'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        // Spec 13a rule 4: bundled or downloaded rules.
        if (rulesVersion != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(l.rulesVersion(rulesVersion), key: const Key('rulesVersion'), style: AppText.sm),
          ),
        AppCard(
          surface: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('⚗', style: AppText.title14.copyWith(color: AppColors.em)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.labTitle, style: AppText.title13),
                    const SizedBox(height: 2),
                    Text(l.labInfo, style: AppText.sm),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(l.labTemplates, style: AppText.title13),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in LabTemplate.values)
              _Chip(
                key: Key('tpl-${t.name}'),
                label: t.label(l),
                color: t.color,
                selected: t == _template,
                onTap: () => _pick(t),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(l.labSenderLabel, style: AppText.label),
        const SizedBox(height: 6),
        // The keyboard must not learn (save) pasted SMS or OTP text: no IME learning, suggestions or autocorrect.
        TextField(
          key: const Key('labSender'),
          controller: _sender,
          enableIMEPersonalizedLearning: false,
          enableSuggestions: false,
          autocorrect: false,
          style: AppText.body13,
          onChanged: (_) => setState(() => _template = null),
        ),
        const SizedBox(height: 12),
        Text(l.labBodyLabel, style: AppText.label),
        const SizedBox(height: 6),
        TextField(
          key: const Key('labBody'),
          controller: _body,
          minLines: 5,
          maxLines: 8,
          enableIMEPersonalizedLearning: false,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.multiline,
          style: AppText.body13,
          onChanged: (_) => setState(() => _template = null),
        ),
        const SizedBox(height: 12),
        Text(l.simLabel, style: AppText.label),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final s in SimSlot.values)
            _Chip(
              key: Key('labSim-${s.name}'),
              label: s.label(l),
              color: AppColors.em,
              selected: s == _sim,
              onTap: () => setState(() => _sim = s),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: AppButton.outline(key: const Key('labParse'), label: l.labParse, onPressed: _parse)),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton.primary(key: const Key('labInject'), label: l.labInject, onPressed: _busy ? null : _inject),
          ),
        ]),
        if (result != null) ...[
          const SizedBox(height: 12),
          AppCard(
            borderColor: (kept ? AppColors.em : AppColors.wa).withValues(alpha: 0.5),
            child: Row(children: [
              Text(kept ? '✔' : '⚠', style: AppText.body13.copyWith(color: kept ? AppColors.em : AppColors.wa)),
              const SizedBox(width: 8),
              Expanded(child: Text(result.label(l), key: const Key('labKeepResult'), style: AppText.body12)),
            ]),
          ),
        ],
        if (_parsed != null) ...[
          const SizedBox(height: 12),
          ParseResultCard(parsed: _parsed!),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.color, required this.selected, required this.onTap});

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.cd,
          border: Border.all(color: selected ? color : AppColors.bd),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: AppText.chip.copyWith(color: selected ? color : AppColors.t1)),
      ),
    );
  }
}
