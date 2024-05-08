import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';

class PubSub<K, V> {
  // Note that this is NOT run as part of a Computed computation.
  // It is just a regular function
  final V Function(K key) computeKey;
  final void Function() onListen;
  final void Function() onCancel;

  PubSub(this.computeKey, this.onListen, this.onCancel);

  // This is a no-op on the keys which have no subscribers
  void recomputeKeys(Set<K> keysToRecompute) {
    final intersection =
        keysToRecompute.intersection(_keyValueStreams.keys.toSet());

    for (var key in intersection) {
      _keyValueStreams[key]!.add(computeKey(key));
    }
  }

  void recomputeAllKeys() {
    for (var e in _keyValueStreams.entries) {
      e.value.add(computeKey(e.key));
    }
  }

  void pubError(Object error) {
    for (var e in _keyValueStreams.entries) {
      e.value.addError(error);
    }
  }

  Computed<V> sub(K key) {
    final myStream = ValueStream<V>();
    ValueStream<V>? leaderStream;

    void onCancel_() {
      if (!leaderStream!.hasListener) {
        final removed = _keyValueStreams.remove(key);
        assert(removed != null);
        leaderStream = null;
        if (_keyValueStreams.isEmpty) {
          onCancel();
        }
      } else {
        leaderStream = null;
      }
    }

    V f() {
      if (leaderStream == null) {
        if (_keyValueStreams.isEmpty) {
          onListen();
        }
        leaderStream = _keyValueStreams.putIfAbsent(key, () => myStream);
        if (identical(leaderStream, myStream)) {
          // This key gained its first listener - computed its value with the provided key computer
          // Using immediately evaluated lambdas for control flow - nasty
          () {
            final V value;
            try {
              value = computeKey(key);
            } catch (e) {
              myStream.addError(e);
              return; // Note that this only exits the lambda
            }
            myStream.add(value);
          }();
        }
      }
      return leaderStream!.use;
    }

    return Computed<V>(f,
        onDispose: (_) => onCancel_(), onDisposeError: (_) => onCancel_());
  }

  final _keyValueStreams = <K, ValueStream<V>>{};
}
