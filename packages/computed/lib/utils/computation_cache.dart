import 'dart:async';

import 'package:meta/meta.dart';

import '../computed.dart';

class _MockScheduledDone<V> {
  var _scheduled = false;
  var _done = false;

  _MockScheduledDone();
}

class ComputationCache<K, V> {
  final _m = <K, Computed<V>>{};
  V Function(K key)? _mock;
  final _mocks = <K, _MockScheduledDone<V>>{};
  final void Function(V value)? _dispose;
  final void Function()? _onCancel;
  final bool _memoized;
  final bool _assertIdempotent;

  ComputationCache(
      {bool memoized = true,
      bool assertIdempotent = true,
      void Function(V value)? dispose,
      void Function()? onCancel})
      : _memoized = memoized,
        _assertIdempotent = assertIdempotent,
        _dispose = dispose,
        _onCancel = onCancel;

  Computed<V> wrap(K key, V Function() computation) {
    final cachedComputation = _m[key];
    if (cachedComputation != null) return cachedComputation;
    late final Computed<V> newComputation;

    void onCancel() {
      final cachedComputation = _m[key];
      if (identical(cachedComputation, newComputation)) {
        final removed = _m.remove(key);
        assert(removed != null);
      }
      if (_mock != null) {
        // ignore: invalid_use_of_visible_for_testing_member
        newComputation.unmock();
        final removed = _mocks.remove(key);
        assert(removed != null);
      }
      if (_onCancel != null) _onCancel!();
    }

    newComputation = Computed(() {
      final cachedComputation = _m[key];
      if (cachedComputation != null &&
          !identical(cachedComputation, newComputation))
        return cachedComputation.use;
      // No cached result
      _m[key] = newComputation;
      if (_mock != null) {
        // We are mocked
        final mad = _mocks.putIfAbsent(key, () => _MockScheduledDone());
        // Schedule a call to `.mock` on ourselves if it has not been called or at least scheduled yet.
        if (!mad._done && !mad._scheduled) {
          // Bypass the Computed's zone
          Zone.current.parent!.run(() => scheduleMicrotask(() {
                if (_mock == null) return; // Unmocked in the meantime
                final mad = _mocks.putIfAbsent(key, () => _MockScheduledDone());
                if (!mad._done) {
                  // ignore: invalid_use_of_visible_for_testing_member
                  newComputation.mock(() => _mock!(key));
                  mad._done = true;
                }
              }));
          mad._scheduled = true;
        }
        throw NoValueException(); // No value yet
      }
      return computation();
    },
        memoized: _memoized,
        assertIdempotent: _assertIdempotent,
        dispose: _dispose,
        onCancel: onCancel);
    return newComputation;
  }

  /// Replaces the original [f] of the computations with [mock].
  ///
  /// See [Computed.mock].
  @visibleForTesting
  void mock(V Function(K key) mock) {
    _mock = mock;
    // Mock all the existing leader computations
    for (var e in _m.entries) {
      final cachedComputation = e.value;
      _mocks.update(e.key, (mad) => mad.._done = true,
          ifAbsent: () => _MockScheduledDone().._done = true);
      // ignore: invalid_use_of_visible_for_testing_member
      cachedComputation.mock(() => mock(e.key));
    }
  }

  /// Unmock the computations.
  ///
  /// See [Computed.unmock].
  @visibleForTesting
  void unmock() {
    _mock = null;
    _mocks.clear();
    // Unmock all the existing leader computations
    for (var c in _m.values) {
      // ignore: invalid_use_of_visible_for_testing_member
      c.unmock();
    }
  }
}
