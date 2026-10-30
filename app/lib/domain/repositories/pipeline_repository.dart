import '../models/pipeline_state.dart';

/// Spec 13a: the phone-to-server pipeline as the screens see it.
abstract interface class PipelineRepository {
  Stream<PipelineState> watch();

  /// The signed device-deactivate call. false when it did not reach the server (no internet).
  Future<bool> deactivateDevice();

  /// Forgets the deviceId (logout). The key and installId stay, so a later login re-registers the same phone.
  Future<void> clearDeviceConfig();
}
