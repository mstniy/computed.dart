import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/merging_change_stream.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

@immutable
class _Option<T> {
  final bool _is;
  final T? _value;

  _Option.some(this._value) : _is = true;
  _Option.none()
      : _is = false,
        _value = null;

  bool operator ==(Object other) =>
      other is _Option &&
      ((_is && other._is && _value == other._value) || (!_is && !other._is));

  @override
  String toString() => _is ? '_Option.some($_value)' : '_Option.none()';
}

class MapValuesComputedComputedMap<K, V, VParent>
    with OperatorsMixin<K, V>, MockMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final Computed<V> Function(K key, VParent value) _convert;
  late final Computed<bool> isEmpty;
  late final Computed<bool> isNotEmpty;
  late final Computed<int> length;
  late final MergingChangeStream<K, V> _changes;
  late final Computed<ChangeEvent<K, V>> _changesComputed;
  var _changesState = <K, ComputedSubscription<V>>{};
  late final Computed<IMap<K, V>> snapshot;

  final keyComputations = ComputationCache<K, V?>();
  final keyOptionComputations = ComputationCache<K, _Option<V>>();
  final containsKeyComputations = ComputationCache<K, bool>();
  final containsValueComputations = ComputationCache<V, bool>();

  MapValuesComputedComputedMap(this._parent, this._convert) {
    final _computedChanges = Computed(() {
      final change = _parent.changes.use;
      return switch (change) {
        ChangeEventReplace<K, VParent>() => ChangeEventReplace(change
            .newCollection
            .map(((key, value) => MapEntry(key, _convert(key, value))))),
        KeyChanges<K, VParent>() =>
          KeyChanges(IMap.fromEntries(change.changes.entries.map((e) {
            final key = e.key;
            return switch (e.value) {
              ChangeRecordValue<VParent>(value: var value) =>
                MapEntry(key, ChangeRecordValue(_convert(key, value))),
              ChangeRecordDelete<VParent>() =>
                MapEntry(key, ChangeRecordDelete<Computed<V>>()),
            };
          }))),
      };
    }, assertIdempotent: false);

    void _computationListener(K key, V value) {
      _changes.add(KeyChanges(
          <K, ChangeRecord<V>>{key: ChangeRecordValue<V>(value)}.lock));
    }

    void _computedChangesListener(ChangeEvent<K, Computed<V>> computedChanges) {
      if (computedChanges is ChangeEventReplace<K, Computed<V>>) {
        final newChangesState = <K, ComputedSubscription<V>>{};
        computedChanges.newCollection.forEach((key, value) {
          newChangesState[key] = value.listen(
              (e) => _computationListener(key, e), _changes.addError);
        });
        _changesState.values.forEach((sub) => sub.cancel());
        _changesState = newChangesState;
        _changes.add(ChangeEventReplace(<K, V>{}.lock));
      } else if (computedChanges is KeyChanges<K, Computed<V>>) {
        for (var e in computedChanges.changes.entries) {
          final key = e.key;
          final change = e.value;
          if (change is ChangeRecordValue<Computed<V>>) {
            final oldSub = _changesState[key];
            _changesState[key] = change.value
                .listen((e) => _computationListener(key, e), _changes.addError);
            oldSub?.cancel();
            // Emit a deletion event, as the key won't have a value until the next microtask
            // Note that if the new computation has a value already, this will be overwritten
            // by [_computationListener].
            _changes.add(KeyChanges(
                <K, ChangeRecord<V>>{key: ChangeRecordDelete<V>()}.lock));
          } else if (change is ChangeRecordDelete<Computed<V>>) {
            _changesState[key]?.cancel();
            _changesState.remove(key);
            _changes.add(KeyChanges(
                <K, ChangeRecord<V>>{key: ChangeRecordDelete<V>()}.lock));
          }
        }
      }
    }

    ComputedSubscription<ChangeEvent<K, Computed<V>>>?
        _computedChangesSubscription;
    _changes = MergingChangeStream(onListen: () {
      assert(_computedChangesSubscription == null);
      _computedChangesSubscription =
          _computedChanges.listen(_computedChangesListener, _changes.addError);
    }, onCancel: () {
      _changesState.values.forEach((sub) => sub.cancel());
      _changesState.clear();
      _computedChangesSubscription!.cancel();
      _computedChangesSubscription = null;
    });
    _changesComputed = $(() => _changes.use);
    snapshot = ChangeStreamComputedMap(_changes, () {
      final entries = _parent.snapshot.use
          .map(((key, value) => MapEntry(key, _convert(key, value))));
      var gotNVE = false;
      final unwrapped = IMap.fromEntries(entries.entries.map((e) {
        try {
          return [MapEntry(e.key, e.value.use)];
        } on NoValueException {
          gotNVE = true;
          return <MapEntry<K, V>>[];
          // Keep going, we want Computed to be aware of all the dependencies
        }
      }).expand((e) => e));

      if (gotNVE) throw NoValueException();
      return unwrapped;
    }).snapshot;

    // To know the length of the collection we do indeed need to compute the values for all the keys
    // as just because a key exists on the parent does not mean it also exists in us
    // because the corresponding computation might not have a value yet
    length = $(() => snapshot.use.length);

    // TODO: We can be slightly smarter about this by not evaluating any computation as soon as
    //  one of them gains a value. Cannot think of an easy way to implement this, though.
    isEmpty = $(() => length.use == 0);
    isNotEmpty = $(() => length.use > 0);
  }

  @override
  Computed<ChangeEvent<K, V>> get changes => _changesComputed;

  Computed<_Option<V>> _getKeyOptionComputation(K key) {
    // This logic is extracted to a separate cache so that the mapped computations'
    // results are shared between `operator[]` and `containsKey`.
    final computationComputation = Computed(() {
      if (_parent.containsKey(key).use) {
        return _convert(key, _parent[key].use as VParent);
      }
      return null;
    }, assertIdempotent: false);
    // We could mock this cache also, but it would be extra code for likely little gain.
    // So `operator[]` and `containsKey` further wraps it to separate caches and let
    // the [MockMixin] handle it.
    return keyOptionComputations.wrap(key, () {
      final c = computationComputation.use;
      if (c == null) {
        // The key does not exist in the parent
        return _Option.none();
      }
      try {
        return _Option.some(c.use);
      } on NoValueException {
        return _Option.none();
      }
    });
  }

  @override
  Computed<V?> operator [](K key) {
    final keyOptionComputation = _getKeyOptionComputation(key);
    final resultComputation = keyComputations.wrap(key, () {
      final option = keyOptionComputation.use;
      if (!option._is)
        return null; // The key does not exist in the parent or the mapped computations has no value yet
      // The key exists in the parent and the mapped computation has a value
      return option._value;
    });

    return resultComputation;
  }

  @override
  Computed<bool> containsKey(K key) {
    final keyOptionComputation = _getKeyOptionComputation(key);
    final resultComputation = containsKeyComputations.wrap(key, () {
      final option = keyOptionComputation.use;
      if (!option._is)
        return false; // The key does not exist in the parent or the mapped computations has no value yet
      // The key exists in the parent and the mapped computation has a value
      return true;
    });

    return resultComputation;
  }

  @override
  Computed<bool> containsValue(V value) => containsValueComputations.wrap(
      value, () => snapshot.use.containsValue(value));
}
