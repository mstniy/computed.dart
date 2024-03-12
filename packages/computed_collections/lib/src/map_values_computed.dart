import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

class _SubscriptionAndProduced<T> {
  late ComputedSubscription<T> _sub;
  bool _produced = false;

  _SubscriptionAndProduced();
}

class MapValuesComputedComputedMap<K, V, VParent>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final Computed<V> Function(K key, VParent value) _convert;
  late final ValueStream<ChangeEvent<K, V>> _changes;
  late final Computed<ChangeEvent<K, V>> _changesComputed;
  final _changesState = <K, _SubscriptionAndProduced<V>>{};
  late final Computed<IMap<K, V>> _snapshot;
  final _keyComputationCache = ComputationCache<K, V?>();

  MapValuesComputedComputedMap(this._parent, this._convert) {
    // We use async here because Computed does not have semantics operator==
    final _computedChanges = Computed.async(() {
      final change = _parent.changes.use;
      if (change is ChangeEventReplace<K, VParent>) {
        return ChangeEventReplace(change.newCollection
            .map(((key, value) => MapEntry(key, _convert(key, value)))));
      } else if (change is KeyChanges<K, VParent>) {
        return KeyChanges(IMap.fromEntries(change.changes.entries.map((e) {
          final key = e.key;
          final upstreamChange = e.value;
          if (upstreamChange is ChangeRecordInsert<VParent>) {
            return MapEntry(
                key, ChangeRecordInsert(_convert(key, upstreamChange.value)));
          } else if (upstreamChange is ChangeRecordUpdate<VParent>) {
            return MapEntry(
                key,
                ChangeRecordUpdate<Computed<V>>(
                    _convert(key, upstreamChange.newValue)));
          } else if (upstreamChange is ChangeRecordDelete<VParent>) {
            return MapEntry(key, ChangeRecordDelete<Computed<V>>());
          } else {
            throw TypeError();
          }
        })));
      } else {
        throw TypeError();
      }
    });

    void _computationListener(_SubscriptionAndProduced<V> sap, K key, V value) {
      _changes.add(KeyChanges({
        key: sap._produced
            ? ChangeRecordUpdate<V>(value)
            : ChangeRecordInsert<V>(value)
      }.lock));
      sap._produced = true;
    }

    void _computedChangesListener(ChangeEvent<K, Computed<V>> computedChanges) {
      if (computedChanges is ChangeEventReplace<K, Computed<V>>) {
        _changesState.values.forEach((sap) => sap._sub.cancel());
        _changesState
            .clear(); // TODO: Delay the cancellation to remove the microtask lag
        _changes.add(ChangeEventReplace(<K, V>{}.lock));
        computedChanges.newCollection.forEach((key, value) {
          final sap = _SubscriptionAndProduced<V>();
          sap._sub = value.listen(
              (e) => _computationListener(sap, key, e), _changes.addError);
          _changesState[key] = sap;
        });
      } else if (computedChanges is KeyChanges<K, Computed<V>>) {
        for (var e in computedChanges.changes.entries) {
          final key = e.key;
          final change = e.value;
          if (change is ChangeRecordInsert<Computed<V>>) {
            assert(_changesState[key] == null);
            final sap = _SubscriptionAndProduced<V>();
            sap._sub = change.value.listen(
                (e) => _computationListener(sap, key, e), _changes.addError);
            _changesState[key] = sap;
          } else if (change is ChangeRecordUpdate<Computed<V>>) {
            final sap = _changesState[key]!;
            final oldSub = sap._sub;
            sap._sub = change.newValue.listen(
                (e) => _computationListener(sap, key, e), _changes.addError);
            oldSub.cancel();
            // Emit a deletion event if this key used to exist
            if (sap._produced) {
              _changes.add(KeyChanges({key: ChangeRecordDelete<V>()}.lock));
              sap._produced = false;
            }
          } else if (change is ChangeRecordDelete<Computed<V>>) {
            final sap = _changesState[key]!;
            sap._sub.cancel();
            _changesState.remove(key);
            if (sap._produced) {
              _changes.add(KeyChanges({key: ChangeRecordDelete<V>()}.lock));
            }
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
      _changesState.values.forEach((sap) => sap._sub.cancel());
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
