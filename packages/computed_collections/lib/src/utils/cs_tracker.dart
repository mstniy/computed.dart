import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/src/utils/option.dart';
import 'package:computed_collections/src/utils/value_or_exception.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../change_event.dart';

class CSTracker<K, V> {
  ValueOrException<IMap<K, V>>? _snapshot;
  final Computed<ChangeEvent<K, V>> _changeStream;
  late final Computed<IMap<K, V>> _snapshotStream;
  ComputedSubscription<ChangeEvent<K, V>>? _changeSubscription;
  ComputedSubscription<IMap<K, V>>? _snapshotSubscription;

  final _keyStreams = <K, ValueStream<Option<V>>>{};
  final _valueStreams = <V, ValueStream<bool>>{};

  CSTracker(this._changeStream, this._snapshotStream);

  void _pubAll(IMap<K, V> m) {
    final oldSnapshot = _snapshot;
    _snapshot = ValueOrException.value(m);
    // If we are changing from one well-behaved snapshot to another,
    // iterate over either the set of streams or the set of keys
    // in both the old and the new snapshots, whichever is smaller.
    if (!(oldSnapshot?.isValue ?? false) ||
        _keyStreams.length <= oldSnapshot!.value.length + m.length) {
      for (var e in _keyStreams.entries) {
        e.value.add(
            m.containsKey(e.key) ? Option.some(m[e.key] as V) : Option.none());
      }
    } else {
      for (var key in oldSnapshot.value.keys) {
        if (!m.containsKey(key)) {
          _keyStreams[key]?.add(Option.none());
        }
      }
      for (var e in m.entries) {
        _keyStreams[e.key]?.add(Option.some(e.value));
      }
    }
    for (var e in _valueStreams.entries) {
      e.value.add(m.containsValue(e.key));
    }
  }

  void _onSnapshot(IMap<K, V> m) {
    _snapshotSubscription!.cancel();
    _snapshotSubscription = null;
    _pubAll(m);
  }

  // This is a no-op on the keys which have no subscribers
  void _onChange(ChangeEvent<K, V> e) {
    switch (e) {
      case KeyChanges<K, V>(changes: final changes):
        // We assert that a) there is an existing snapshot and b) it is not an exception
        var s = _snapshot!.value;
        for (var e in changes.entries) {
          switch (e.value) {
            case ChangeRecordValue<V>(value: final value):
              s = s.add(e.key, value);
              _keyStreams[e.key]?.add(Option.some(value));
              _valueStreams[value]?.add(true);
            case ChangeRecordDelete<V>():
              if (s.containsKey(e.key)) {
                final snew = s.remove(e.key);
                final oldValue = s[e.key] as V;
                if (_valueStreams.containsValue(oldValue)) {
                  // Note that this could be further optimized by keeping a set of keys
                  // containing each value, at the cost of additional memory.
                  _valueStreams[oldValue]!.add(snew.containsValue(oldValue));
                }
                _keyStreams[e.key]?.add(Option.none());
                s = snew;
              }
          }
        }
        _snapshot = ValueOrException.value(s);
      case ChangeEventReplace<K, V>():
        _pubAll(e.newCollection);
    }
  }

  void _onStreamError(Object error) {
    _changeSubscription?.cancel();
    _changeSubscription = null;
    _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    _snapshot = ValueOrException.exc(error);
    for (var s in _keyStreams.values) {
      s.addError(error);
    }
    for (var s in _valueStreams.values) {
      s.addError(error);
    }
  }

  void _maybeCancelSubs() {
    if (_keyStreams.isEmpty && _valueStreams.isEmpty) {
      _snapshot = null;
      _changeSubscription?.cancel();
      _changeSubscription = null;
      _snapshotSubscription?.cancel();
      _snapshotSubscription = null;
    }
  }

  void _maybeCreateSubs() {
    if (_keyStreams.isEmpty && _valueStreams.isEmpty) {
      _snapshotSubscription =
          _snapshotStream.listen(_onSnapshot, _onStreamError);
      _changeSubscription = _changeStream.listen(_onChange, _onStreamError);
    }
  }

  ValueStream<Option<V>> _maybeInitKeyStream(K key) {
    void onCancel_() {
      final removed = _keyStreams.remove(key);
      assert(removed != null);
      _maybeCancelSubs();
    }

    return _keyStreams.putIfAbsent(key, () {
      _maybeCreateSubs();
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
  }

  Computed<bool> containsKey(K key) {
    return Computed.async(() {
      final leaderStream = _maybeInitKeyStream(key);
      return leaderStream.use.is_;
    });
  }

  Computed<V?> operator [](K key) {
    return Computed.async(() {
      final leaderStream = _maybeInitKeyStream(key);
      return leaderStream.use.value;
    });
  }

  Computed<bool> containsValue(V value) {
    void onCancel_() {
      final removed = _valueStreams.remove(value);
      assert(removed != null);
      _maybeCancelSubs();
    }

    return Computed.async(() {
      final leaderStream = _valueStreams.putIfAbsent(value, () {
        _maybeCreateSubs();
        // This value gained its first listener - get its presence from the snapshot, if there is one
        final s = ValueStream<bool>(onCancel: onCancel_);
        if (_snapshot != null) {
          if (_snapshot!.isValue) {
            s.add(_snapshot!.value_!.containsValue(value));
          } else {
            s.addError(_snapshot!.exc_!);
          }
        }
        return s;
      });
      return leaderStream.use;
    });
  }
}
