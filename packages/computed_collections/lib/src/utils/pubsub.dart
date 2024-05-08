import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';

class PubSub<K, V> {
  // Note that this is NOT run as part of a Computed computation.
  // It is just a regular function
  final V Function(K key) computeKey;
  final void Function(K key) onKeyCancel;

  PubSub(this.computeKey, this.onKeyCancel);

  Iterable<K> get subbedKeys => _keyValueStreams.keys;
  void pub(K key, V value) {
    final s = _keyValueStreams[key];
    if (s == null) return; // No subscriber for this key - noop
    s.add(value);
  }

  void pubError(K key, Object error) {
    final s = _keyValueStreams[key];
    if (s == null) return; // No subscriber for this key - noop
    s.addError(error);
  }

  Computed<V> sub(K key) {
    final myStream = ValueStream<V>();
    ValueStream<V>? leaderStream;

    void onCancel() {
      if (!leaderStream!.hasListener) {
        final removed = _keyValueStreams.remove(key);
        assert(removed != null);
        leaderStream = null;
        onKeyCancel(key);
      } else {
        leaderStream = null;
      }
    }

    V f() {
      if (leaderStream == null) {
        leaderStream = _keyValueStreams.putIfAbsent(key, () => myStream);
        if (identical(leaderStream, myStream)) {
          // This key gained its first listener - computed its value with the provided key computer
          myStream.add(computeKey(key));
        }
      }
      return leaderStream!.use;
    }

    return Computed<V>(f,
        onDispose: (_) => onCancel(), onDisposeError: (_) => onCancel());
  }

  final _keyValueStreams = <K, ValueStream<V>>{};
}
