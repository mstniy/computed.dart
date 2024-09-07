import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/merging_change_stream.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'expandos.dart';
import 'utils/option.dart';
import 'utils/cs_tracker.dart';

class MapValuesComputedComputedMap<K, V, VParent>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final Computed<V> Function(K key, VParent value) _convert;

  final _keyOptionComputations =
      ComputationCache<K, Option<V>>(assertIdempotent: false);

  late final CSTracker<K, V> _tracker;

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

    late final MergingChangeStream<K, V> _changes;
    var _changesState = <K, ComputedSubscription<V>>{};

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
    changes = $(() => _changes.use);
    snapshot = snapshotComputation(changes, () {
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
    });

    _tracker = CSTracker(changes, snapshot);
  }

  Computed<Option<V>> _getKeyOptionComputation(K key) {
    // This logic is extracted to a separate cache so that the mapped computations'
    // results are shared between `operator[]` and `containsKey`.
    final parentContainsKey = _parent.containsKey(key);
    final parentKey = _parent[key];
    final computationComputation = Computed(() {
      if (parentContainsKey.use) {
        return _convert(key, parentKey.use as VParent);
      }
      return null;
    }, assertIdempotent: false);
    return _keyOptionComputations.wrap(key, () {
      try {
        final s = snapshot.useWeak;
        // useWeak returned - means there is an existing non-weak listener on the snapshot
        if (s.containsKey(key)) return Option.some(s[key] as V);
        return Option.none();
      } on NoStrongUserException {
        // Pass
      } on CyclicUseException {
        // Pass - we get this if the computation of one keys depends on the computation of another key
      }
      final c = computationComputation.use;
      if (c == null) {
        // The key does not exist in the parent
        return Option.none();
      }
      try {
        return Option.some(c.use);
      } on NoValueException {
        return Option.none();
      }
    });
  }

  @override
  Computed<V?> operator [](K key) {
    final keyOptionComputation = _getKeyOptionComputation(key);
    return $(() {
      final option = keyOptionComputation.use;
      if (!option.is_)
        return null; // The key does not exist in the parent or the mapped computations has no value yet
      // The key exists in the parent and the mapped computation has a value
      return option.value;
    });
  }

  @override
  Computed<bool> containsKey(K key) {
    final keyOptionComputation = _getKeyOptionComputation(key);
    return $(() {
      final option = keyOptionComputation.use;
      if (!option.is_)
        return false; // The key does not exist in the parent or the mapped computations has no value yet
      // The key exists in the parent and the mapped computation has a value
      return true;
    });
  }

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  late final Computed<ChangeEvent<K, V>> changes;

  @override
  late final Computed<IMap<K, V>> snapshot;

  // TODO: We can be slightly smarter about this by not evaluating any computation as soon as
  //  one of them gains a value. Cannot think of an easy way to do this, though.
  @override
  Computed<bool> get isEmpty =>
      isEmptyExpando[this] ??= $(() => snapshot.use.isEmpty);
  @override
  Computed<bool> get isNotEmpty =>
      isNotEmptyExpando[this] ??= $(() => snapshot.use.isNotEmpty);
  // To know the length of the collection we do indeed need to compute the values for all the keys
  // as just because a key exists on the parent does not mean it also exists in us
  // because the corresponding computation might not have a value yet
  @override
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);
}
