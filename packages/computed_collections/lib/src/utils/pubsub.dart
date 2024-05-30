import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';

class PubSub<K, V> {
  final V Function(K key) computeValue;
  final void Function() onListen;
  final void Function() onCancel;

  PubSub(this.computeValue, this.onListen, this.onCancel);

  // This is a no-op on the keys which have no subscribers
  void recomputeKeys(Set<K> keysToRecompute) {
    final intersection =
        keysToRecompute.intersection(_keyValueStreams.keys.toSet());

    for (var key in intersection) {
      _keyValueStreams[key]!.add(computeValue(key));
    }
  }

  void recomputeAllKeys() {
    for (var e in _keyValueStreams.entries) {
      e.value.add(computeValue(e.key));
    }
  }

  void pubError(Object error) {
    for (var e in _keyValueStreams.entries) {
      e.value.addError(error);
    }
  }

  Computed<V> sub(K key) {
    void onCancel_() {
      final removed = _keyValueStreams.remove(key);
      assert(removed != null);
      if (_keyValueStreams.isEmpty) {
        onCancel();
      }
    }

    return Computed.async(() {
      final leaderStream = _keyValueStreams.putIfAbsent(key, () {
        if (_keyValueStreams.isEmpty) {
          onListen();
        }
        // This key gained its first listener - compute its value with the provided key computer
        final s = ValueStream<V>(onCancel: onCancel_);
        // Using immediately evaluated lambdas for control flow - nasty
        () {
          final V value;
          try {
            value = computeValue(key);
          } catch (e) {
            s.addError(e);
            return; // Note that this only exits the lambda
          }
          s.add(value);
        }();
        return s;
      });
      return leaderStream.use;
    });
  }

  final _keyValueStreams = <K, ValueStream<V>>{};
}
