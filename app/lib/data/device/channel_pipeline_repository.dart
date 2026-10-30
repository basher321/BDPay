import 'dart:async';

import '../../domain/models/pipeline_state.dart';
import '../../domain/repositories/pipeline_repository.dart';
import 'sms_channel.dart';

/// Spec 13a: getPipelineState() at start and on every "pipeline" event. Never logs.
class ChannelPipelineRepository implements PipelineRepository {
  ChannelPipelineRepository(this._native);

  final DeviceNative _native;
  final _changes = StreamController<PipelineState>.broadcast();
  StreamSubscription<String>? _events;
  PipelineState? _current;

  PipelineState? get current => _current;

  void start() {
    _events ??= _native.events.listen((e) {
      if (e == 'pipeline' || e == 'rules') unawaited(refresh());
    });
    unawaited(refresh());
  }

  void dispose() => _events?.cancel();

  Future<void> refresh() async {
    try {
      final s = PipelineState.fromMap(await _native.getPipelineState());
      _current = s;
      _changes.add(s);
    } on Exception {
      // Keep the last state.
    }
  }

  @override
  Stream<PipelineState> watch() async* {
    final c = _current;
    if (c != null) yield c;
    yield* _changes.stream;
  }

  @override
  Future<bool> deactivateDevice() async {
    try {
      return await _native.deactivateDevice();
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> clearDeviceConfig() async {
    await _native.clearDeviceConfig();
    await refresh();
  }
}
