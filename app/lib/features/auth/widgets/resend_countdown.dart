import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'auth_layout.dart';

/// "{s} সেকেন্ড পরে আবার পাঠানো যাবে" for 60 s, then the "আবার কোড পাঠান" link.
/// [onResend] returns true when a new code was sent, which restarts the countdown.
class ResendCountdown extends StatefulWidget {
  const ResendCountdown({super.key, required this.onResend});

  static const seconds = 60;

  final Future<bool> Function() onResend;

  @override
  State<ResendCountdown> createState() => _ResendCountdownState();
}

class _ResendCountdownState extends State<ResendCountdown> {
  Timer? _timer;
  int _left = ResendCountdown.seconds;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _left = ResendCountdown.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (_busy) return;
    setState(() => _busy = true);
    final sent = await widget.onResend();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (sent) _start();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_left > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(l.resendIn(_left), key: const Key('resendIn'), textAlign: TextAlign.center, style: AppText.sm),
      );
    }
    return AuthLink(key: const Key('resendLink'), label: l.resendCode, onTap: _busy ? null : _resend);
  }
}
