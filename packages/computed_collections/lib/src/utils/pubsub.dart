import 'dart:async';

import 'package:computed/computed.dart';

import 'option.dart';

class PubSub<K, V> {
  // Note that this is NOT run as part of a Computed computation.
  // It is just a regular function
  final Option<V> Function(K key) computeKey;

  PubSub(this.computeKey);

  Iterable<K> get subbedKeys => _keyValueStreams.keys;
  void pub(K key, V value) {
    final s = _keyValueStreams[key];
    if (s == null) return; // No subscriber for this key - noop
    s.$2.add(value);
  }

  void pubError(K key, Object error) {
    final s = _keyValueStreams[key];
    if (s == null) return; // No subscriber for this key - noop
    s.$2.addError(error);
  }

  Computed<V> sub(K key) {
    late final Computed<V> computation;

    void maybeStepDown() {
      // _keyValueStreams[key] might be null because the leader's onDispose is called before the followers'
      if (identical(_keyValueStreams[key]?.$1, computation)) {
        // We are the leader
        _keyValueStreams.remove(key);
      }
    }

    computation = Computed(() {
      final leaderS = _keyValueStreams.putIfAbsent(
          key, () => (computation, StreamController.broadcast()));

      if (identical(leaderS.$1, computation)) {
        // If we are the leader, use the created stream, falling back to the provided value computer
        try {
          return leaderS.$2.stream.use;
        } catch (NoValueException) {
          final res = computeKey(key);
          if (res.is_) return res.value as V;
          throw NoValueException;
        }
      } else {
        return leaderS.$1.use; // Otherwise, use the leader
      }
    },
        onDispose: (_) => maybeStepDown(),
        onDisposeError: (_) => maybeStepDown());

    return computation;
  }

  final _keyValueStreams = <K, (Computed<V>, StreamController<V>)>{};
}
