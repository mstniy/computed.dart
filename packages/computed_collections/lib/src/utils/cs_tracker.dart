import 'package:computed/computed.dart';
import 'package:computed/src/computed.dart';
import 'package:computed_collections/src/utils/option.dart';
import 'package:computed_collections/src/utils/value_or_exception.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../change_event.dart';

class _CustomDownstream extends ComputedImpl<void> {
  Set<Computed> _downstream;
  _CustomDownstream(void Function() f, this._downstream)
      : super(f, false, false, false, null, null);

  @override
  // Cannot subscribe to this - it will "push" updates instead
  void get use => throw UnsupportedError('cannot use');

  @override
  void get useWeak => throw UnsupportedError('cannot useWeak');

  @override
  void get prev => throw UnsupportedError('cannot prev');

  @override
  Set<Computed> eval() {
    super.eval();
    return _downstream;
  }
}

class CSTracker<K, V> {
  ValueOrException<IMap<K, V>>? _snapshot;

  late final _CustomDownstream _pusher;
  ComputedSubscription<void>? _pusherSub;

  final _keyStreams = <K, Computed<Option<V>>>{};
  final _valueStreams = <V, Computed<bool>>{};

  CSTracker(Computed<ChangeEvent<K, V>> changeStream,
      Computed<IMap<K, V>> snapshotStream) {
    final downstream = <Computed>{};

    void _onException(Object e) {
      _snapshot = ValueOrException.exc(e);
      // Broadcast the exception to all the key/value streams
      downstream.addAll({..._keyStreams.values, ..._valueStreams.values});
    }

    _pusher = _CustomDownstream(() {
      downstream.clear();
      if (_snapshot != null && !_snapshot!.isValue) {
        // "cancelOnError" semantics
        throw NoValueException();
      }
      final sOld = _snapshot;
      try {
        _snapshot = ValueOrException.value(snapshotStream.use);
      } on NoValueException {
        rethrow; // Not much to do if we don't have a snapshot
      } catch (e) {
        _onException(e);
        return;
      }
      final ChangeEvent<K, V> change;
      try {
        change = changeStream.use;
      } on NoValueException {
        // TODO: This logic breaks down when used on eg. a ConstComputedMap
        throw NoValueException();
      } catch (e) {
        _onException(e);
        return;
      }
      // "push" the update to the relevant streams by returning them as our downstream
      downstream.addAll(switch (change) {
        KeyChanges<K, V>(changes: final changes) => sOld == null
            ? {..._keyStreams.values, ..._valueStreams.values}
            : {
                // iterate over either the set of streams or the set of keys
                // in both the old and the new snapshots, whichever is smaller.
                ...changes.entries
                    .where((e) =>
                        _keyStreams.containsKey(e.key) &&
                        switch (e.value) {
                          ChangeRecordValue<V>(value: final value) =>
                            !sOld.value_!.containsKey(e.key) ||
                                sOld.value_![e.key] != value,
                          ChangeRecordDelete<V>() =>
                            sOld.value_!.containsKey(e.key),
                        })
                    .map((e) => _keyStreams[e.key]!),
                ...changes.entries
                    .where((e) =>
                        sOld.value_!.containsKey(e.key) &&
                        _valueStreams.containsKey(sOld.value_![e.key]))
                    .map((e) => _valueStreams[sOld.value_![e.key]]!),
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
      });
    }, downstream);
  }

  void _maybeCancelSub() {
    if (_keyStreams.isEmpty && _valueStreams.isEmpty) {
      _snapshot = null;
      _pusherSub!.cancel();
      _pusherSub = null;
    }
  }

  void _maybeCreateSub() {
    _pusherSub ??= _pusher.listen(null,
        (e) {}); // Swallow the exceptions here, as key/value streams handle it themselves
  }

  Computed<Option<V>> _maybeInitKeyStream(K key) {
    void onCancel_() {
      final removed = _keyStreams.remove(key);
      assert(removed != null);
      _maybeCancelSub();
    }

    return _keyStreams.putIfAbsent(key, () {
      final s = Computed<Option<V>>.async(() {
        _maybeCreateSub();
        // Note that this computation does not .use anything
        //  it is instead ran by the snapshot computation using "push" semantics
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
                _maybeCreateSub();
                // Note that this computation does not .use anything
                //  it is instead ran by the snapshot computation using "push" semantics
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
