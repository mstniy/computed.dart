import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

class MapValuesComputedComputedMap<K, V, VParent>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final Computed<V> Function(K key, VParent value) _convert;
  late final ValueStream<ChangeEvent<K, V>> _changes;
  late final Computed<ChangeEvent<K, V>> _changesComputed;
  var _changesState = <K, ComputedSubscription<V>>{};
  late final Computed<IMap<K, V>> _snapshot;
  final _keyComputationCache = ComputationCache<K, V?>();

  MapValuesComputedComputedMap(this._parent, this._convert) {
    final _computedChanges = Computed(() {
      final change = _parent.changes.use;
      if (change is ChangeEventReplace<K, VParent>) {
        return ChangeEventReplace(change.newCollection
            .map(((key, value) => MapEntry(key, _convert(key, value)))));
      } else if (change is KeyChanges<K, VParent>) {
        return KeyChanges(IMap.fromEntries(change.changes.entries.map((e) {
          final key = e.key;
          final upstreamChange = e.value;
          if (upstreamChange is ChangeRecordValue<VParent>) {
            return MapEntry(
                key, ChangeRecordValue(_convert(key, upstreamChange.value)));
          } else if (upstreamChange is ChangeRecordDelete<VParent>) {
            return MapEntry(key, ChangeRecordDelete<Computed<V>>());
          } else {
            throw TypeError();
          }
        })));
      } else {
        throw TypeError();
      }
    }, assertIdempotent: false);

    ChangeEvent<K, V>? _changesLastAdded;
    void _changesAddMerge(ChangeEvent<K, V> change) {
      if (_changesLastAdded == null) {
        _changesLastAdded = change;
        scheduleMicrotask(() {
          _changesLastAdded = null;
        });
        _changes.add(change);
        return;
      }
      if (change is ChangeEventReplace<K, V>) {
        _changesLastAdded = change;
        _changes.add(change);
      } else {
        assert(change is KeyChanges<K, V>);
        if (_changesLastAdded is KeyChanges<K, V>) {
          _changesLastAdded = KeyChanges((_changesLastAdded as KeyChanges<K, V>)
              .changes
              .addAll((change as KeyChanges<K, V>).changes));
          _changes.add(_changesLastAdded!);
        } else {
          assert(_changesLastAdded is ChangeEventReplace<K, V>);
          final keyChanges = (change as KeyChanges<K, V>).changes;
          final keyDeletions =
              keyChanges.entries.where((e) => e.value is ChangeRecordDelete<K>);
          _changesLastAdded = ChangeEventReplace(
              (_changesLastAdded as ChangeEventReplace<K, V>)
                  .newCollection
                  .addEntries(keyChanges.entries
                      .where((e) => e.value is! ChangeRecordDelete<K>)
                      .map((e) => MapEntry(
                          e.key, (e.value as ChangeRecordValue<V>).value))));
          keyDeletions.forEach((e) => _changesLastAdded = ChangeEventReplace(
              (_changesLastAdded as ChangeEventReplace<K, V>)
                  .newCollection
                  .remove(e.key)));
          _changes.add(_changesLastAdded!);
        }
      }
    }

    void _computationListener(K key, V value) {
      _changesAddMerge(KeyChanges(
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
        _changesAddMerge(ChangeEventReplace(<K, V>{}.lock));
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
            _changesAddMerge(KeyChanges(
                <K, ChangeRecord<V>>{key: ChangeRecordDelete<V>()}.lock));
          } else if (change is ChangeRecordDelete<Computed<V>>) {
            _changesState[key]?.cancel();
            _changesState.remove(key);
            _changesAddMerge(KeyChanges(
                <K, ChangeRecord<V>>{key: ChangeRecordDelete<V>()}.lock));
          }
        }
      }
    }

    ComputedSubscription<ChangeEvent<K, Computed<V>>>?
        _computedChangesSubscription;
    _changes = ValueStream(onListen: () {
      assert(_computedChangesSubscription == null);
      _computedChangesSubscription =
          _computedChanges.listen(_computedChangesListener, _changes.addError);
    }, onCancel: () {
      _changesState.values.forEach((sub) => sub.cancel());
      _changesState.clear();
      _computedChangesSubscription!.cancel();
    });
    _changesComputed = $(() => _changes.use);
    _snapshot = ChangeStreamComputedMap(_changes, () {
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
  }

  @override
  Computed<ChangeEvent<K, V>> get changes => _changesComputed;

  @override
  Computed<bool> containsKey(K key) => _parent.containsKey(key);

  @override
  Computed<bool> get isEmpty => _parent.isEmpty;

  @override
  Computed<bool> get isNotEmpty => _parent.isNotEmpty;

  @override
  Computed<int> get length => _parent.length;

  @override
  Computed<IMap<K, V>> get snapshot => _snapshot;

  @override
  Computed<V?> operator [](K key) {
    final computationComputation = Computed(() {
      if (_parent.containsKey(key).use) {
        return _convert(key, _parent[key].use as VParent);
      }
      return null;
    }, assertIdempotent: false);
    final resultComputation = _keyComputationCache.wrap(key, () {
      try {
        return computationComputation.use?.use;
      } on NoValueException {
        return null;
      }
    });

    return resultComputation;
  }

  @override
  Computed<bool> containsValue(V value) {
    // TODO: implement containsValue
    throw UnimplementedError();
  }

  @override
  void fix(IMap<K, V> value) {
    // TODO: implement fix
  }

  @override
  void fixThrow(Object e) {
    // TODO: implement fixThrow
  }

  @override
  void mock(IMap<K, V> Function() mock) {
    // TODO: implement mock
  }

  @override
  void unmock() {
    // TODO: implement unmock
  }
}
