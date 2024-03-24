import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/merging_change_stream.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

class MapValuesComputedComputedMap<K, V, VParent>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final Computed<V> Function(K key, VParent value) _convert;
  late final MergingChangeStream<K, V> _changes;
  late final Computed<ChangeEvent<K, V>> _changesComputed;
  var _changesState = <K, ComputedSubscription<V>>{};
  late final Computed<IMap<K, V>> _snapshot;
  final _keyComputationCache = ComputationCache<K, V?>();

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
