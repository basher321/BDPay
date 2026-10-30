import 'package:flutter/foundation.dart';

/// Spec 13a: the phone pipeline's state from getPipelineState(). None of it is a secret.
@immutable
class PipelineState {
  const PipelineState({
    this.deviceId,
    this.revoked = false,
    this.clockOffsetMs = 0,
    this.rulesVersion = 0,
    this.lastServerContactAt,
    this.latestAppVersion,
    this.appDownloadUrl,
  });

  static const empty = PipelineState();

  factory PipelineState.fromMap(Map<String, Object?> m) {
    final contact = (m['lastServerContactMs'] as num?)?.toInt();
    return PipelineState(
      deviceId: m['deviceId'] as String?,
      revoked: m['revoked'] == true,
      clockOffsetMs: (m['clockOffsetMs'] as num?)?.toInt() ?? 0,
      rulesVersion: (m['rulesVersion'] as num?)?.toInt() ?? 0,
      lastServerContactAt: contact == null ? null : DateTime.fromMillisecondsSinceEpoch(contact, isUtc: true),
      latestAppVersion: m['latestAppVersion'] as String?,
      appDownloadUrl: m['appDownloadUrl'] as String?,
    );
  }

  final String? deviceId;
  final bool revoked;
  final int clockOffsetMs;
  final int rulesVersion;

  /// UTC.
  final DateTime? lastServerContactAt;

  /// Spec 15: the newest app version and its download page, from the last heartbeat (null when not configured).
  final String? latestAppVersion;
  final String? appDownloadUrl;

  /// Registered with the server and not revoked.
  bool get active => deviceId != null && !revoked;
}
