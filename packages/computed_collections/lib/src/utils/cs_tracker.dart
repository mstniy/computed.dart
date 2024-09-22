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

    Set<Computed> allStreams() =>
        {..._keyStreams.values, ..._valueStreams.values};

    _pusher = CustomDownstream(() {
      // If [_snapshot] is an exception, this throws.
      // This allows us to have cancelOnError semantics
      final sOld = _snapshot?.value;
      try {
        _snapshot = ValueOrException.value(snapshotStream.use);
      } on NoValueException {
        rethrow; // Not much to do if we don't have a snapshot
      } catch (e) {
        _snapshot = ValueOrException.exc(e);
        return allStreams();
      }
      final ChangeEvent<K, V> change;
      try {
        change = changeStream.use;
      } on NoValueException {
        // For the initial snapshot we always have to notify all streams
        //  as they have not been initialized yet.
        return sOld == null ? allStreams() : {};
      }
      // Check again here
      if (sOld == null) {
        return allStreams();
      }
      // We don't catch other exceptions here - instead assuming
      //  the snapshot stream would have thrown them.
      // "push" the update to the relevant streams by returning them as our downstream
      return switch (change) {
        KeyChanges<K, V>(changes: final changes) =>
          // TODO: iterate over either the set of streams or the set of keys
          //  in both the old and the new snapshots, whichever is smaller.
          changes.entries
              .expand((e) => [
                    if (_keyStreams.containsKey(e.key)) _keyStreams[e.key]!,
                    if (sOld.containsKey(e.key) &&
                        _valueStreams.containsKey(sOld[e.key]))
                      _valueStreams[sOld[e.key]]!,
                    ...switch (e.value) {
                      ChangeRecordValue<V>(value: final v)
                          when _valueStreams.containsKey(v) =>
                        [
                          _valueStreams[
                              (e.value as ChangeRecordValue<V>).value]!
                        ],
                      _ => <Computed>[],
                    }
                  ])
              .toSet(),
        ChangeEventReplace<K, V>() => allStreams()
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
                return _snapshot!.value.containsValue(value);
              }, onCancel: onCancel_));
      return leaderStream.use;
    });
  }
}
