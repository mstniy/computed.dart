import 'dart:async';

import 'package:computed/utils/streams.dart';
import 'package:rxdart/rxdart.dart' show BehaviorSubject;

import 'option.dart';

class PubSub<K, V> {
  // Note that this is NOT run as part of a Computed computation.
  // It is just a regular function
  final Option<V> Function(K key) computeKey;
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

  ValueStream<V> sub(K key) {
    StreamSubscription<V>? sub;
    late ValueStream<V> self;

    void leaderOnCancel() {
      final removed = _keyValueStreams.remove(key);
      assert(removed != null);
      onKeyCancel(key);
    }

    void followerOnCancel() {
      sub!.cancel();
      sub = null;
    }

    void onListen() {
      var newLeader = false;
      final leaderS = _keyValueStreams.putIfAbsent(key, () {
        newLeader = true;
        // Leaders are sync because the only listeners are followers,
        // which themselves do not run arbitrary code and are not sync.
        return BehaviorSubject(
            onCancel: leaderOnCancel,
            sync: true); // TODO: Does BehaviourSubject have == dedup?
      });

      if (newLeader) {
        () {
          Option<V> res;
          try {
            res = computeKey(key);
          } catch (e) {
            leaderS.addError(e);
            return; // Why does Dart not have try-catch-else :(
          }
          if (res.is_) {
            leaderS.add(res.value as V);
          }
        }();
      }

      // Follow the leader
      sub = leaderS.listen(self.add, onError: self.addError);
      // Sure, the leader will tell this to us, but in a separate microtask
      if (leaderS.hasError) {
        self.addError(leaderS.error);
      } else if (leaderS.hasValue) {
        self.add(leaderS.value);
      }
    }

    self = ValueStream<V>(onListen: onListen, onCancel: followerOnCancel);
    return self;
  }

  final _keyValueStreams = <K, BehaviorSubject<V>>{};
}
