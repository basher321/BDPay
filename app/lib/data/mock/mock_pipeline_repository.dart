import '../../domain/models/pipeline_state.dart';
import '../../domain/repositories/pipeline_repository.dart';
import 'mock_store.dart';

/// MOCK - used by tests and when no server is configured. Not registered (deviceId null), rules version 1.
class MockPipelineRepository implements PipelineRepository {
  MockPipelineRepository([PipelineState state = const PipelineState(rulesVersion: 1)]) : _state = MockStore(state);

  final MockStore<PipelineState> _state;

  bool deactivateResult = true;
  int deactivateCalls = 0;
  int clearCalls = 0;

  set state(PipelineState s) => _state.value = s;

  PipelineState get state => _state.value;

  @override
  Stream<PipelineState> watch() => _state.watch();

  @override
  Future<bool> deactivateDevice() async {
    deactivateCalls++;
    return deactivateResult;
  }

  @override
  Future<void> clearDeviceConfig() async {
    clearCalls++;
    final s = _state.value;
    _state.value = PipelineState(rulesVersion: s.rulesVersion, lastServerContactAt: s.lastServerContactAt);
  }
}
