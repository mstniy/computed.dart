import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:computed_collections/src/utils/merging_change_stream.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'expandos.dart';
import 'utils/option.dart';
import 'utils/cs_tracker.dart';

class MapValuesComputedComputedMap<K, V, VParent>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  final ComputedMap<K, VParent> _parent;
  final Computed<V> Function(K key, VParent value) _convert;

  final _keyOptionComputations =
      ComputationCache<K, Option<V>>(assertIdempotent: false);

  late final CSTracker<K, V> _tracker;

  MapValuesComputedComputedMap(this._parent, this._convert) {
    final computedChanges = Computed(() {
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

    late final MergingChangeStream<K, V> merger;
    var changesState = <K, ComputedSubscription<void>>{};

    ComputedSubscription<void> listenToNestedComputation(
        K k, Computed<V> nested) {
      return Computed.async(() {
        final value = nested.use;
        merger.add(
            KeyChanges(<K, ChangeRecord<V>>{k: ChangeRecordValue(value)}.lock));
      },
              dispose: (_) => merger.add(KeyChanges(
                  <K, ChangeRecord<V>>{k: ChangeRecordDelete<V>()}.lock)))
          .listen(null);
    }

    void setState(IMap<K, Computed<V>> m) {
      for (var s in changesState.values) {
        s.cancel();
      }
      changesState =
          m.unlock.map((k, c) => MapEntry(k, listenToNestedComputation(k, c)));
    }

    void computedChangesListener(
        ChangeEvent<K, Computed<V>> computedChangesValue) {
      switch (computedChangesValue) {
        case ChangeEventReplace<K, Computed<V>>():
          merger.add(ChangeEventReplace(<K, V>{}.lock));
          setState(computedChangesValue.newCollection);
        case KeyChanges<K, Computed<V>>():
          for (var e in computedChangesValue.changes.entries) {
            final key = e.key;
            final change = e.value;
            // Note that this emits a deletion event for the key, if it has a value,
            // and we want that as the key won't have a value until the next microtask.
            // Note that if the new computation has a value already, this will be overwritten
            // by the computation in [_listenToNestedComputation].
            changesState[key]?.cancel();
            switch (change) {
              case ChangeRecordValue<Computed<V>>():
                changesState[key] =
                    listenToNestedComputation(key, change.value);
              case ChangeRecordDelete<Computed<V>>():
                changesState.remove(key);
            }
          }
      }
    }

    ComputedSubscription<ChangeEvent<K, Computed<V>>>?
        computedChangesSubscription;
    merger = MergingChangeStream(onListen: () {
      assert(computedChangesSubscription == null);
      computedChangesSubscription =
          computedChanges.listen(computedChangesListener, merger.addError);
    }, onCancel: () {
      for (var sub in changesState.values) {
        sub.cancel();
      }
      changesState.clear();
      computedChangesSubscription!.cancel();
      computedChangesSubscription = null;
    });
    changes = $(() => merger.use);
    snapshot = snapshotComputation(changes, () {
      setState(_parent.snapshot.use
          .map((key, value) => MapEntry(key, _convert(key, value))));
      return IMap<K, V>.empty();
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
      if (!option.is_) {
        return null; // The key does not exist in the parent or the mapped computations has no value yet
      }
      // The key exists in the parent and the mapped computation has a value
      return option.value;
    });
  }

  @override
  Computed<bool> containsKey(K key) {
    final keyOptionComputation = _getKeyOptionComputation(key);
    return $(() {
      final option = keyOptionComputation.use;
      if (!option.is_) {
        return false; // The key does not exist in the parent or the mapped computations has no value yet
      }
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
