import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:computed_collections/src/utils/get_if_changed.dart';
import 'package:computed_collections/src/utils/merging_change_stream.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'expandos.dart';
import 'utils/cs_tracker.dart';

class FlatComputedMap<K1, K2, V>
    with OperatorsMixin<(K1, K2), V>
    implements ComputedMap<(K1, K2), V> {
  final ComputedMap<K1, ComputedMap<K2, V>> _parent;

  late final CSTracker<(K1, K2), V> _tracker;

  FlatComputedMap(this._parent) {
    Map<K1, ComputedSubscription<void>>?
        keySubs; // null if we have not received an initial snapshot from the upstream

    late final MergingChangeStream<(K1, K2), V> merger;

    ComputedSubscription<void> listenToNestedMap(
        K1 k1, ComputedMap<K2, V> nested) {
      final snapshotComputation = nested.snapshot;
      final changeStream = nested.changes;
      final initialPrevToken = IMap<K2, V>.empty();
      return Computed<IMap<K2, V>>.withPrev((prev) {
        final IMap<K2, V> snap;
        final ChangeEvent<K2, V>? change;
        try {
          snap = snapshotComputation.use;
          change = getIfChanged(changeStream);
        } on NoValueException {
          // This must be coming from the nested snapshot
          // Can't do much without a snapshot
          throw NoValueException();
        } catch (e) {
          merger.addError(e);
          // Throwing the exception causes withPrev to stop computing us
          rethrow;
        }

        IMap<K2, V>? snapPrev;
        try {
          snapPrev = snapshotComputation.prev;
        } on NoValueException {
          // Leave null
        }

        if (identical(prev, initialPrevToken)) {
          // This is the initial snapshot - broadcast the new key products
          merger.add(KeyChanges(
              snap.map((k2, v) => MapEntry((k1, k2), ChangeRecordValue(v)))));
        } else if (change != null) {
          switch (change) {
            case KeyChanges<K2, V>():
              merger.add(KeyChanges(
                  change.changes.map((k2, r) => MapEntry((k1, k2), r))));
            case ChangeEventReplace<K2, V>():
              if (snapPrev != null) {
                // Broadcast a deletion for all the key products of the old snapshot
                merger.add(KeyChanges(snapPrev.map(
                    (k2, _) => MapEntry((k1, k2), ChangeRecordDelete<V>()))));
              }
              // Broadcast the new key products
              merger.add(KeyChanges(change.newCollection
                  .map((k2, v) => MapEntry((k1, k2), ChangeRecordValue(v)))));
          }
        }
        return snap;
      },
              initialPrev: initialPrevToken,
              async: true,
              dispose: (snap) => merger.add(KeyChanges(snap
                  .map((k2, _) => MapEntry((k1, k2), ChangeRecordDelete())))))
          // Explicitly ignore exceptions thrown by the computation,
          // as they must be coming from the nested map and we handle
          // them by adding them to the merger before throwing ourselves
          .listen(null, (_) {});
    }

    void setM(IMap<K1, ComputedMap<K2, V>> m) {
      for (var s in keySubs?.values ?? <ComputedSubscription<void>>[]) {
        s.cancel();
      }
      keySubs =
          m.unlock.map((k1, cm) => MapEntry(k1, listenToNestedMap(k1, cm)));
    }

    final computedChanges = Computed.async(() {
      if (keySubs == null) {
        setM(_parent.snapshot.use);
      }
      final change = _parent.changes.use;
      return switch (change) {
        ChangeEventReplace<K1, ComputedMap<K2, V>>() => ChangeEventReplace(
            change.newCollection.map(((key, value) => MapEntry(key, value)))),
        KeyChanges<K1, ComputedMap<K2, V>>() =>
          KeyChanges(IMap.fromEntries(change.changes.entries.map((e) {
            final key = e.key;
            return switch (e.value) {
              ChangeRecordValue<ComputedMap<K2, V>>(value: var value) =>
                MapEntry(key, ChangeRecordValue(value)),
              ChangeRecordDelete<ComputedMap<K2, V>>() =>
                MapEntry(key, ChangeRecordDelete<ComputedMap<K2, V>>()),
            };
          }))),
      };
    });

    void computedChangesListener(
        ChangeEvent<K1, ComputedMap<K2, V>> computedChangesValue) {
      switch (computedChangesValue) {
        case ChangeEventReplace<K1, ComputedMap<K2, V>>():
          merger.add(ChangeEventReplace(<(K1, K2), V>{}.lock));
          // Note that _setM may add new changes, eg if one of the
          // maps in the new set of values is a const map
          setM(computedChangesValue.newCollection);
        case KeyChanges<K1, ComputedMap<K2, V>>():
          for (var e in computedChangesValue.changes.entries) {
            final k1 = e.key;
            final change = e.value;
            keySubs![k1]
                ?.cancel(); // Note that this emits deletion events for the old key products, if a snapshot exists
            switch (change) {
              case ChangeRecordValue<ComputedMap<K2, V>>():
                keySubs![k1] = listenToNestedMap(k1, change.value);
              case ChangeRecordDelete<ComputedMap<K2, V>>():
                keySubs!.remove(k1);
            }
          }
      }
    }

    ComputedSubscription<ChangeEvent<K1, ComputedMap<K2, V>>>?
        computedChangesSubscription;
    merger = MergingChangeStream(onListen: () {
      assert(computedChangesSubscription == null);
      computedChangesSubscription =
          computedChanges.listen(computedChangesListener, merger.addError);
    }, onCancel: () {
      for (var sub in keySubs?.values ?? <ComputedSubscription<void>>[]) {
        sub.cancel();
      }
      keySubs = null;
      computedChangesSubscription!.cancel();
      computedChangesSubscription = null;
    });
    changes = $(() => merger.use);
    snapshot = snapshotComputation(changes, null);

    _tracker = CSTracker(changes, snapshot);
  }

  @override
  Computed<V?> operator []((K1, K2) key) {
    final parentK1 = _parent[key.$1];
    final parentK1K2 =
        Computed(() => parentK1.use?[key.$2], assertIdempotent: false);
    return $(() => parentK1K2.use?.use);
  }

  @override
  Computed<bool> containsKey((K1, K2) key) {
    final parentContainsK1 = _parent.containsKey(key.$1);
    final parentK1 = _parent[key.$1];
    final parentK1K2 = Computed(
        () => parentContainsK1.use ? parentK1.use!.containsKey(key.$2) : null,
        assertIdempotent: false);
    return $(() => parentK1K2.use?.use ?? false);
  }

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  late final Computed<ChangeEvent<(K1, K2), V>> changes;

  @override
  late final Computed<IMap<(K1, K2), V>> snapshot;

  @override
  Computed<bool> get isEmpty =>
      isEmptyExpando[this] ??= $(() => snapshot.use.isEmpty);
  @override
  Computed<bool> get isNotEmpty =>
      isNotEmptyExpando[this] ??= $(() => snapshot.use.isNotEmpty);

  @override
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);
}
