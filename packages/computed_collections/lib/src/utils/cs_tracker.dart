import 'package:computed/computed.dart';
import 'package:computed_collections/src/utils/option.dart';
import 'package:computed_collections/src/utils/value_or_exception.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../change_event.dart';
import 'custom_downstream.dart';

class CSTracker<K, V> {
  ValueOrException<IMap<K, V>>? _snapshot;

  late final CustomDownstream _pusher;

  final _keyStreams = <K, Computed<Option<V>>>{};
  final _valueStreams = <V, Computed<bool>>{};

  CSTracker(Computed<ChangeEvent<K, V>> changeStream,
      Computed<IMap<K, V>> snapshotStream) {
    final downstream = <Computed>{};

    Set<Computed> _allStreams() =>
        {..._keyStreams.values, ..._valueStreams.values};

    void _onException(Object e) {
      _snapshot = ValueOrException.exc(e);
    }

    _pusher = CustomDownstream(() {
      // If [_snapshot] is an exception, this throws.
      // This allows us to have cancelOnError semantics
      final sOld = _snapshot?.value;
      try {
        _snapshot = ValueOrException.value(snapshotStream.use);
      } on NoValueException {
        rethrow; // Not much to do if we don't have a snapshot
      } catch (e) {
        _onException(e);
        return _allStreams();
      }
      final ChangeEvent<K, V> change;
      try {
        change = changeStream.use;
      } on NoValueException {
        if (sOld == null) {
          // TODO: iterate over either the set of streams or the set of keys
          //  in the snapshot, whichever is smaller.
          return _allStreams();
        }
        return {};
      } catch (e) {
        _onException(e);
        return _allStreams();
      }
      // "push" the update to the relevant streams by returning them as our downstream
      return switch (change) {
        KeyChanges<K, V>(changes: final changes) => sOld == null
            ? {..._keyStreams.values, ..._valueStreams.values}
            : {
                // TODO: iterate over either the set of streams or the set of keys
                //  in both the old and the new snapshots, whichever is smaller.
                ...changes.entries
                    .where((e) =>
                        _keyStreams.containsKey(e.key) &&
                        switch (e.value) {
                          ChangeRecordValue<V>(value: final value) =>
                            !sOld.containsKey(e.key) || sOld[e.key] != value,
                          ChangeRecordDelete<V>() => sOld.containsKey(e.key),
                        })
                    .map((e) => _keyStreams[e.key]!),
                ...changes.entries
                    .where((e) =>
                        sOld.containsKey(e.key) &&
                        _valueStreams.containsKey(sOld[e.key]))
                    .map((e) => _valueStreams[sOld[e.key]]!),
                ...changes.values
                    .where((ce) =>
                        ce is ChangeRecordValue<V> &&
                        _valueStreams.containsKey(ce.value))
                    .map((ce) =>
                        _valueStreams[(ce as ChangeRecordValue<V>).value]!)
              },
        ChangeEventReplace<K, V>() => {
            ..._keyStreams.values,
            ..._valueStreams.values
          }
      };
    }, downstream);
  }

  void _maybeCancelSub() {
    if (_keyStreams.isEmpty && _valueStreams.isEmpty) {
      _snapshot = null;
    }
  }

  Computed<Option<V>> _maybeInitKeyStream(K key) {
    void onCancel_() {
      final removed = _keyStreams.remove(key);
      assert(removed != null);
      _maybeCancelSub();
    }

    return _keyStreams.putIfAbsent(key, () {
      final s = Computed<Option<V>>.async(() {
        _pusher.use;
        // Note that this computation is ran by the
        // [_pusher] using "push" semantics
        if (_snapshot == null) {
          throw NoValueException(); // Wait until we get a snapshot
        }
        final snapshot = _snapshot!.value;
        return snapshot.containsKey(key)
            ? Option.some(snapshot[key] as V)
            : Option.none();
      }, onCancel: onCancel_);
      return s;
    });
  }

  Computed<bool> containsKey(K key) {
    return $(() {
      final leaderStream = _maybeInitKeyStream(key);
      return leaderStream.use.is_;
    });
  }

  Computed<V?> operator [](K key) {
    return $(() {
      final leaderStream = _maybeInitKeyStream(key);
      return leaderStream.use.value;
    });
  }

  Computed<bool> containsValue(V value) {
    void onCancel_() {
      final removed = _valueStreams.remove(value);
      assert(removed != null);
      _maybeCancelSub();
    }

    return $(() {
      final leaderStream = _valueStreams.putIfAbsent(
          value,
          () => Computed.async(() {
                _pusher.use;
                //s Note that this computation is ran by the
                // [_pusher] using "push" semantics.
                // Note that this could be further optimized by keeping a set of keys
                // containing each value, at the cost of additional memory.
                if (_snapshot == null) {
                  throw NoValueException(); // Wait until we get a snapshot
                }
                return _snapshot!.value.containsValue(value);
              }, onCancel: onCancel_));
      return leaderStream.use;
    });
  }
}
