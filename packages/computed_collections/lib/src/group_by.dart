import 'package:computed/computed.dart';
import 'package:computed_collections/src/utils/custom_downstream.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../change_event.dart';
import '../computedmap.dart';
import 'computedmap_mixins.dart';
import 'cs.dart';
import 'utils/cs_tracker.dart';
import 'utils/snapshot_computation.dart';
import 'utils/group_by.dart';
import 'expandos.dart';

final class _GroupInfo<KParent, V> {
  ChangeEvent<KParent, V>? lastChange; // If null -> no change yet
  Computed<ChangeEvent<KParent, V>> cs;
  bool csHasSubscribers = false;
  IMap<KParent, V> snapshot;
  Computed<IMap<KParent, V>> ss;
  bool ssHasSubscribers = false;
  ComputedMap<KParent, V> m;

  _GroupInfo(this.snapshot, this.cs, this.ss, this.m);
}

class GroupByComputedMap<K, V, KParent>
    with OperatorsMixin<K, ComputedMap<KParent, V>>
    implements ComputedMap<K, ComputedMap<KParent, V>> {
  final ComputedMap<KParent, V> _parent;
  final K Function(KParent key, V value) _convert;

  late final CSTracker<K, ComputedMap<KParent, V>> _tracker;
  late final Computed<(ChangeEvent<K, ComputedMap<KParent, V>>?, Set<Computed>)>
      _keyChangesAndDownstream;
  late final CustomDownstream _pusher;

  var _mappedKeys = <KParent, K>{};
  Object? _exc;
  Map<K, _GroupInfo<KParent, V>>? _m = null;
  var _initialValue = true;

  void _onCancel() {
    _mappedKeys = {};
    _m = null;
    _exc = null;
    _initialValue = true;
  }

  Computed<ChangeEvent<KParent, V>> _makeCS(K key) {
    late final Computed<ChangeEvent<KParent, V>> self;
    self = Computed(() {
      final g = _m?[key];

      if (g?.cs != self) {
        // Defunct computation
        throw NoValueException();
      }

      g!.csHasSubscribers = true;

      _pusher.use;
      if (g.lastChange == null) throw NoValueException();
      return g.lastChange!;
    }, onCancel: () {
      final g = _m?[key];

      if (g?.cs != self) {
        // Defunct computation
        return;
      }

      g!.csHasSubscribers = false;
    });
    return self;
  }

  Computed<IMap<KParent, V>> _makeSS(K key) {
    late final Computed<IMap<KParent, V>> self;
    self = Computed(() {
      final g = _m?[key];

      if (g?.ss != self) {
        // Defunct computation
        throw NoValueException();
      }

      g!.ssHasSubscribers = true;

      _pusher.use;
      return g.snapshot;
    }, onCancel: () {
      final g = _m?[key];

      if (g?.ss != self) {
        // Defunct computation
        return;
      }

      g!.ssHasSubscribers = false;
    });
    return self;
  }

  IMap<K, ComputedMap<KParent, V>> _setM(IMap<KParent, V> m) {
    final (grouped, mappedKeys) = m.groupBy(_convert);

    _m = grouped.map((k, v) {
      final cs = _makeCS(k);
      final ss = _makeSS(k);
      final map = ChangeStreamComputedMap(cs, snapshotStream: ss);
      return MapEntry(k, _GroupInfo(v.lock, cs, ss, map));
    });
    _mappedKeys = mappedKeys;

    return _m!.map((k, v) {
      return MapEntry<K, ComputedMap<KParent, V>>(k, v.m);
    }).lock;
  }

  GroupByComputedMap(this._parent, this._convert) {
    _keyChangesAndDownstream = Computed.async(() {
      if (_exc != null) {
        throw _exc!; // "cancelOnError"
      }

      // We need a snapshot from the parent before we can begin
      // computing the change stream.
      if (_m == null) {
        final s = _parent.snapshot.use;
        _setM(s);
      }

      ChangeEvent<KParent, V>? change;

      try {
        change = _parent.changes.use;
      } on NoValueException {
        // Pass
      } catch (e) {
        _exc = e;
        throw e;
      }

      if (_initialValue) {
        _initialValue = false;
        // Do not report key changes, as this is our initial value
        // But push the new snapshot to the new groups' snapshot computation
        return (
          null,
          _m!.values.where((g) => g.ssHasSubscribers).map((g) => g.ss).toSet()
        );
      }

      // If we ended up here, either the upstream snapshot must have changed
      // or upstream must have broadcast a change. Either way we must have a change.
      change!;
      switch (change) {
        case ChangeEventReplace<KParent, V>():
          // Same reasoning as the initial snapshot case above
          return (
            ChangeEventReplace(_setM(change.newCollection)),
            _m!.values.where((g) => g.ssHasSubscribers).map((g) => g.ss).toSet()
          );
        case KeyChanges<KParent, V>():
          final (groupedByIsDelete, _) =
              change.changes.groupBy((_, e) => e is ChangeRecordDelete);
          final deletedKeys =
              groupedByIsDelete[true]?.keys.toSet() ?? <KParent>{};
          final valueKeysAndGroups = groupedByIsDelete[false]?.map((k, v) =>
                  MapEntry(k, (
                    _convert(k, (v as ChangeRecordValue<V>).value),
                    v.value
                  ))) ??
              <KParent, (K, V)>{};

          final keyChanges = <K, ChangeRecord<ComputedMap<KParent, V>>>{};

          final batchedChanges = <K, KeyChanges<KParent, V>>{};

          for (var e in valueKeysAndGroups.entries) {
            final groupKey = e.value.$1;
            final parentKey = e.key;
            final value = e.value.$2;
            _m!.update(
              groupKey,
              (g) => g..snapshot = g.snapshot.add(parentKey, value),
              ifAbsent: () {
                final snapshot = {parentKey: value}.lock;
                final cs = _makeCS(groupKey);
                final ss = _makeSS(groupKey);
                final m = ChangeStreamComputedMap(cs, snapshotStream: ss);
                keyChanges[groupKey] = ChangeRecordValue(m);
                return _GroupInfo(snapshot, cs, ss, m);
              },
            );
            if (!keyChanges.containsKey(groupKey)) {
              batchedChanges.update(
                  groupKey,
                  (changes) => KeyChanges(changes.changes
                      .add(e.key, ChangeRecordValue(e.value.$2))),
                  ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                        e.key: ChangeRecordValue(e.value.$2)
                      }.lock));
            }
            final hasOldGroup = _mappedKeys.containsKey(parentKey);
            final oldGroupKey = _mappedKeys[parentKey];
            _mappedKeys[parentKey] = groupKey;
            if (hasOldGroup) {
              if (oldGroupKey != groupKey) {
                final oldGroup = _m![oldGroupKey]!;
                oldGroup.snapshot = oldGroup.snapshot.remove(parentKey);
                if (oldGroup.snapshot.isEmpty) {
                  keyChanges[oldGroupKey as K] = ChangeRecordDelete();
                  _m!.remove(oldGroupKey);
                  batchedChanges.remove(oldGroupKey);
                } else {
                  batchedChanges.update(
                      oldGroupKey as K,
                      (changes) => KeyChanges(
                          changes.changes.add(e.key, ChangeRecordDelete<V>())),
                      ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                            e.key: ChangeRecordDelete<V>()
                          }.lock));
                }
              }
            }
          }

          for (var deletedKey in deletedKeys) {
            if (!_mappedKeys.containsKey(deletedKey)) {
              continue; // Extraneous deletion from upstream?
            }
            final oldGroupKey = _mappedKeys.remove(deletedKey) as K;
            final oldGroup = _m![oldGroupKey]!;
            oldGroup.snapshot = oldGroup.snapshot.remove(deletedKey);
            if (oldGroup.snapshot.isEmpty) {
              keyChanges[oldGroupKey] = ChangeRecordDelete();
              _m!.remove(oldGroupKey);
              batchedChanges.remove(oldGroupKey);
            } else {
              batchedChanges.update(
                  oldGroupKey,
                  (changes) => KeyChanges(
                      changes.changes.add(deletedKey, ChangeRecordDelete<V>())),
                  ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                        deletedKey: ChangeRecordDelete<V>()
                      }.lock));
            }
          }

          // Set the groups' last changes and aggregate the downstream
          final downstream = batchedChanges.entries
              .map((e) => _m![e.key]!..lastChange = e.value)
              .map((g) =>
                  [if (g.csHasSubscribers) g.cs, if (g.ssHasSubscribers) g.ss])
              .expand((e) => e)
              .toSet();

          return (KeyChanges(keyChanges.lock), downstream);
      }
    }, onCancel: _onCancel);

    changes = $(() {
      final keyChanges = _keyChangesAndDownstream.use.$1;
      switch (keyChanges) {
        case KeyChanges<K, ComputedMap<KParent, V>>(changes: final changes):
          if (changes.isEmpty) throw NoValueException();
          return keyChanges;
        case ChangeEventReplace<K, ComputedMap<KParent, V>>():
          return keyChanges;
        case null:
          throw NoValueException();
      }
    });

    final downstream = <Computed>{};

    // Allows the group streams to indirectly kick off the computation.
    // Subscribes to _keyAndNestedChanges and routes the change and snapshot events
    // to the groups.
    // Group streams directly subscribing to the change computation would be
    // inefficient, as with each change in the set of groups all groups would
    // be notified.
    _pusher = CustomDownstream(() {
      final Set<Computed> downstream;
      try {
        downstream = _keyChangesAndDownstream.use.$2;
      } catch (e) {
        // _keyChangesAndDownstream must have already assumed a value,
        // as otherwise there would be no groups and we would have no
        // users and not be computed.
        assert(e is! NoValueException);
        // Broadcast the exception to all the streams
        return _m!.values
            .map((g) =>
                [if (g.csHasSubscribers) g.cs, if (g.ssHasSubscribers) g.ss])
            .expand((e) => e)
            .toSet();
      }
      return downstream;
    }, downstream);

    snapshot = snapshotComputation(changes, () {
      // There might already be a subscriber to .changes,
      // so check the internal fields first.
      if (_exc != null) throw _exc!;
      return switch (_m) {
        Map<K, _GroupInfo<KParent, V>>() =>
          _m!.map((k, g) => MapEntry(k, g.m)).lock,
        // No subscriber yet - kick things off
        null => _setM(_parent.snapshot.use),
      };
    });

    _tracker = CSTracker(changes, snapshot);
  }

  @override
  Computed<bool> containsKey(K key) => _tracker.containsKey(key);

  @override
  Computed<ComputedMap<KParent, V>?> operator [](K key) => _tracker[key];

  @override
  Computed<bool> containsValue(ComputedMap<KParent, V> value) =>
      _tracker.containsValue(value);

  @override
  late final Computed<IMap<K, ComputedMap<KParent, V>>> snapshot;

  @override
  late final Computed<ChangeEvent<K, ComputedMap<KParent, V>>> changes;

  @override
  Computed<bool> get isEmpty => _parent.isEmpty;
  @override
  Computed<bool> get isNotEmpty => _parent.isNotEmpty;

  @override
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);
}
