import '../device/sms_channel.dart';

/// Spec 13a: in the app, SMS go to the server from the native background job (SmsUploadWorker), which sends
/// every waiting row in batches and writes the results itself. This only asks it to run now; one upload runs at
/// a time. MockSmsUploader stays for tests and the no-server mode.
class NativeSmsUploader {
  const NativeSmsUploader(this._channel);

  final SmsChannel _channel;

  /// Never throws: the worker also runs on its own (new SMS, internet back, heartbeat).
  Future<void> uploadNow() => _channel.uploadNow().catchError((_) {});
}
