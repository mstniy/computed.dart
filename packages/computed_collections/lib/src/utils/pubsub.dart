import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/src/utils/option.dart';
import 'package:computed_collections/src/utils/value_or_exception.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class PubSub<K, V> {
  ValueOrException<IMap<K, V>>? _snapshot;
  final void Function() onListen;
  final void Function() onCancel;

  PubSub(this.onListen, this.onCancel);

  // This is a no-op on the keys which have no subscribers
  void pubAll(IMap<K, V> m) {
    _snapshot = ValueOrException.value(m);
    for (var e in _keyValueStreams.entries) {
      e.value.add(
          m.containsKey(e.key) ? Option.some(m[e.key] as V) : Option.none());
    }
  }

  // This is a no-op on the keys which have no subscribers
  void pubMany(IMap<K, Option<V>> m) {
    // We assert that a) there is an existing snapshot and b) it is not an exception
    var s = _snapshot!.value;
    for (var e in m.entries) {
      if (e.value.is_) {
        s = s.add(e.key, e.value.value as V);
      } else {
        s = s.remove(e.key);
      }
    }
    _snapshot = ValueOrException.value(s);
    for (var e in _keyValueStreams.entries) {
      if (m.containsKey(e.key)) {
        e.value.add(m[e.key]!);
      }
    }
  }

  void pubError(Object error) {
    _snapshot = ValueOrException.exc(error);
    for (var e in _keyValueStreams.entries) {
      e.value.addError(error);
    }
  }

  Computed<Option<V>> sub(K key) {
    void onCancel_() {
      final removed = _keyValueStreams.remove(key);
      assert(removed != null);
      if (_keyValueStreams.isEmpty) {
        _snapshot = null;
        onCancel();
      }
    }

    return Computed.async(() {
      final leaderStream = _keyValueStreams.putIfAbsent(key, () {
        if (_keyValueStreams.isEmpty) {
          onListen();
        }
        // This key gained its first listener - get its value from the snapshot, if there is one
        final s = ValueStream<Option<V>>(onCancel: onCancel_);
        if (_snapshot != null) {
          if (_snapshot!.isValue) {
            if (_snapshot!.value_!.containsKey(key)) {
              s.add(Option.some(_snapshot!.value_![key] as V));
            } else {
              s.add(Option.none());
            }
          } else {
            s.addError(_snapshot!.exc_!);
          }
        }
        return s;
      });
      return leaderStream.use;
    });
  }

  final _keyValueStreams = <K, ValueStream<Option<V>>>{};
}
