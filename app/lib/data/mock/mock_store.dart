import 'dart:async';

/// Holds one in-memory value. Every new listener first gets the current value, then each change.
class MockStore<T> {
  MockStore(this._value);

  T _value;
  final _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T next) {
    _value = next;
    _changes.add(next);
  }

  Stream<T> watch() {
    StreamSubscription<T>? sub;
    late final StreamController<T> out;
    out = StreamController<T>(
      onListen: () {
        out.add(_value);
        sub = _changes.stream.listen(out.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }
}
