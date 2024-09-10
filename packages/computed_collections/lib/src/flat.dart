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
    final _computedChanges = Computed(() {
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
    }, assertIdempotent: false);

    late final MergingChangeStream<(K1, K2), V> _changes;
    var _keySubs = <K1, ComputedSubscription<void>>{};

    ComputedSubscription<void> _listenToNestedMap(
        K1 k1, ComputedMap<K2, V> nested) {
      final snapshotComputation = nested.snapshot;
      final changeStream = nested.changes;
      final initialPrevToken = IMap<K2, V>.empty();
      return Computed<IMap<K2, V>>.withPrev((prev) {
        final snap = snapshotComputation.use;
        final change = getIfChanged(changeStream);

        IMap<K2, V>? snapPrev;
        try {
          snapPrev = snapshotComputation.prev;
        } on NoValueException {
          // Leave null
        }

        if (identical(prev, initialPrevToken)) {
          // This is the initial snapshot - broadcast the new key products
          _changes.add(KeyChanges(
              snap.map((k2, v) => MapEntry((k1, k2), ChangeRecordValue(v)))));
        } else if (change != null) {
          switch (change) {
            case KeyChanges<K2, V>():
              _changes.add(KeyChanges(
                  change.changes.map((k2, r) => MapEntry((k1, k2), r))));
            case ChangeEventReplace<K2, V>():
              if (snapPrev != null) {
                // Broadcast a deletion for all the key products of the old snapshot
                _changes.add(KeyChanges(snapPrev.map(
                    (k2, _) => MapEntry((k1, k2), ChangeRecordDelete<V>()))));
              }
              // Broadcast the new key products
              _changes.add(KeyChanges(change.newCollection
                  .map((k2, v) => MapEntry((k1, k2), ChangeRecordValue(v)))));
          }
        }
        return snap;
      },
              initialPrev: initialPrevToken,
              async: true,
              dispose: (snap) => _changes.add(KeyChanges(snap
                  .map((k2, _) => MapEntry((k1, k2), ChangeRecordDelete())))))
          .listen(null);
    }

    void _setM(IMap<K1, ComputedMap<K2, V>> m) {
      _keySubs.values.forEach((s) => s.cancel());
      _keySubs =
          m.unlock.map((k1, cm) => MapEntry(k1, _listenToNestedMap(k1, cm)));
    }

    void _computedChangesListener(
        ChangeEvent<K1, ComputedMap<K2, V>> computedChanges) {
      switch (computedChanges) {
        case ChangeEventReplace<K1, ComputedMap<K2, V>>():
          _changes.add(ChangeEventReplace(<(K1, K2), V>{}.lock));
          // Note that _setM may add new changes, eg if one of the
          // maps in the new set of values is a const map
          _setM(computedChanges.newCollection);
        case KeyChanges<K1, ComputedMap<K2, V>>():
          computedChanges.changes.entries.forEach((e) {
            final k1 = e.key;
            final change = e.value;
            switch (change) {
              case ChangeRecordValue<ComputedMap<K2, V>>():
                _keySubs.update(k1, (oldSub) {
                  oldSub
                      .cancel(); // Note that this emits deletion events for the old key products, if a snapshot exists
                  return _listenToNestedMap(k1, change.value);
                }, ifAbsent: () => _listenToNestedMap(k1, change.value));
              case ChangeRecordDelete<ComputedMap<K2, V>>():
                _keySubs[k1]
                    ?.cancel(); // Note that this emits deletion events for the old key products, if a snapshot exists
                _keySubs.remove(k1);
            }
          });
      }
    }

    ComputedSubscription<ChangeEvent<K1, ComputedMap<K2, V>>>?
        _computedChangesSubscription;
    _changes = MergingChangeStream(onListen: () {
      assert(_computedChangesSubscription == null);
      _computedChangesSubscription =
          _computedChanges.listen(_computedChangesListener, _changes.addError);
    }, onCancel: () {
      _keySubs.values.forEach((sub) => sub.cancel());
      _keySubs.clear();
      _computedChangesSubscription!.cancel();
      _computedChangesSubscription = null;
    });
    changes = $(() => _changes.use);
    snapshot = snapshotComputation(changes, () {
      _setM(_parent.snapshot.use);
      return IMap<(K1, K2), V>.empty();
    });

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
