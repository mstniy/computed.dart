import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/src/utils/option.dart';
import 'package:computed_collections/src/utils/value_or_exception.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../change_event.dart';
import 'snapshot_computation.dart';

class PubSub<K, V> {
  ValueOrException<IMap<K, V>>? _snapshot;
  final Computed<ChangeEvent<K, V>> _changeStream;
  late final Computed<IMap<K, V>> _snapshotStream;
  ComputedSubscription<ChangeEvent<K, V>>? _changeSubscription;
  ComputedSubscription<IMap<K, V>>? _snapshotSubscription;

  PubSub(this._changeStream,
      {IMap<K, V> Function()? initialValueComputer,
      Computed<IMap<K, V>>? snapshotStream}) {
    _snapshotStream = snapshotStream ??
        snapshotComputation(_changeStream, initialValueComputer);
  }

  Computed<IMap<K, V>> get snapshot => _snapshotStream;

  void _pubAll(IMap<K, V> m) {
    _snapshot = ValueOrException.value(m);
    for (var e in _keyValueStreams.entries) {
      e.value.add(
          m.containsKey(e.key) ? Option.some(m[e.key] as V) : Option.none());
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
              _keyValueStreams[e.key]?.add(Option.some(value));
            case ChangeRecordDelete<V>():
              s = s.remove(e.key);
              _keyValueStreams[e.key]?.add(Option.none());
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
        _changeSubscription?.cancel();
        _changeSubscription = null;
        _snapshotSubscription?.cancel();
        _snapshotSubscription = null;
      }
    }

    return Computed.async(() {
      final leaderStream = _keyValueStreams.putIfAbsent(key, () {
        if (_keyValueStreams.isEmpty) {
          _snapshotSubscription =
              _snapshotStream.listen(_onSnapshot, _onStreamError);
          _changeSubscription = _changeStream.listen(_onChange, _onStreamError);
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
