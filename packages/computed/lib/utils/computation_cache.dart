import 'dart:async';

import 'package:meta/meta.dart';

import '../computed.dart';

class _MockAndDone<V> {
  V Function() _mock;
  var _scheduled = false;
  var _done = false;

  _MockAndDone(this._mock);
}

class ComputationCache<K, V> {
  final _m = <K, Computed<V>>{};
  final _mocks = <K, _MockAndDone<V>>{};
  final void Function(V value)? _onDispose;
  final void Function(Object error)? _onDisposeError;
  final bool _memoized;
  final bool _assertIdempotent;

  ComputationCache(
      {bool memoized = true,
      bool assertIdempotent = true,
      void Function(V value)? onDispose,
      void Function(Object error)? onDisposeError})
      : _memoized = memoized,
        _assertIdempotent = assertIdempotent,
        _onDispose = onDispose,
        _onDisposeError = onDisposeError;

  Computed<V> wrap(K key, V Function() computation) {
    final cachedComputation = _m[key];
    if (cachedComputation != null) return cachedComputation;
    late final Computed<V> newComputation;

    void onDisposeFinally() {
      final cachedComputation = _m[key];
      if (identical(cachedComputation, newComputation)) {
        _m.remove(key);
      }
    }

    void onDispose(V v) {
      onDisposeFinally();
      if (_onDispose != null) _onDispose!(v);
    }

    void onDisposeError(Object o) {
      onDisposeFinally();
      if (_onDisposeError != null) _onDisposeError!(o);
    }

    newComputation = Computed(() {
      final cachedComputation = _m[key];
      if (cachedComputation != null &&
          !identical(cachedComputation, newComputation))
        return cachedComputation.use;
      // No cached result
      _m[key] = newComputation;
      final mad = _mocks[key];
      if (mad != null) {
        // This key is mocked.
        // Schedule a call to `.mock` on ourselves if it has not been called or at least scheduled yet.
        if (!mad._done && !mad._scheduled) {
          // Bypass the Computed's zone
          Zone.current.parent!.run(() => scheduleMicrotask(() {
                final mad = _mocks[key];
                if (mad != null && !mad._done) {
                  // ignore: invalid_use_of_visible_for_testing_member
                  newComputation.mock(mad._mock);
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
        onDispose: onDispose,
        onDisposeError: onDisposeError);
    return newComputation;
  }

  /// Fixes the result of the computation with the given key to the given value.
  ///
  /// See [Computed.fix].
  @visibleForTesting
  void fix(K key, V value) {
    mock(key, () => value);
  }

  /// Fixes the computation with the given key to throw the given object.
  ///
  /// See [Computed.fixThrow].
  @visibleForTesting
  void fixThrow(K key, Object e) {
    mock(key, () => throw e);
  }

  /// Replaces the original [f] of the computation with the given key with [mock].
  ///
  /// See [Computed.mock].
  @visibleForTesting
  void mock(K key, V Function() mock) {
    // If a leader computation exists, mock it
    final cachedComputation = _m[key];
    final mad = _mocks.update(key, (mad) => mad.._mock = mock,
        ifAbsent: () => _MockAndDone(mock));
    if (cachedComputation != null) {
      // ignore: invalid_use_of_visible_for_testing_member
      cachedComputation.mock(mock);
      mad._done = true;
    }
  }

  /// Unmock the computation with the given key.
  ///
  /// See [Computed.unmock].
  @visibleForTesting
  void unmock(K key) {
    _mocks.remove(key);
    // If a leader computation exists, unmock it
    final cachedComputation = _m[key];
    if (cachedComputation != null) {
      // ignore: invalid_use_of_visible_for_testing_member
      cachedComputation.unmock();
    }
  }
}
