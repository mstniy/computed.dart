import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

class _SubscriptionAndProduced<T> {
  ComputedSubscription<T> _sub;
  bool _produced = false;

  _SubscriptionAndProduced(this._sub);
}

class MapValuesComputedComputedMap<K, V, VParent>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final Computed<V> Function(K key, VParent value) _convert;
  late final ValueStream<ISet<ChangeRecord<K, V>>> _changes;
  late final Computed<ISet<ChangeRecord<K, V>>> _changesComputed;
  final _changesState = <K, _SubscriptionAndProduced<V>>{};
  late final Computed<IMap<K, V>> _snapshot;
  final _keyComputationCache = ComputationCache<K, V?>();

  MapValuesComputedComputedMap(this._parent, this._convert) {
    // We use async here because Computed does not have semantics operator==
    final _computedChanges = Computed.async(() {
      final computedChanges = _parent.changes.use.map((upstreamChange) {
        if (upstreamChange is ChangeRecordInsert<K, VParent>) {
          return ChangeRecordInsert(upstreamChange.key,
              _convert(upstreamChange.key, upstreamChange.value));
        } else if (upstreamChange is ChangeRecordUpdate<K, VParent>) {
          return ChangeRecordUpdate<K, Computed<V>>(upstreamChange.key, null,
              _convert(upstreamChange.key, upstreamChange.newValue));
        } else if (upstreamChange is ChangeRecordDelete<K, VParent>) {
          return ChangeRecordDelete<K, Computed<V>>(upstreamChange.key, null);
        } else if (upstreamChange is ChangeRecordReplace<K, VParent>) {
          return ChangeRecordReplace(upstreamChange.newCollection
              .map(((key, value) => MapEntry(key, _convert(key, value)))));
        } else {
          throw TypeError();
        }
      }).toISet();
      if (computedChanges.isEmpty) throw NoValueException();
      return computedChanges;
    });

    void _computationListener(_SubscriptionAndProduced<V> sap, K key, V value) {
      _changes.add({
        sap._produced
            ? ChangeRecordUpdate<K, V>(key, null, value)
            : ChangeRecordInsert<K, V>(key, value)
      }.lock);
      sap._produced = true;
    }

    void _computedChangesListener(
        ISet<ChangeRecord<K, Computed<V>>> computedChanges) {
      for (var change in computedChanges) {
        if (change is ChangeRecordInsert<K, Computed<V>>) {
          assert(_changesState[change.key] == null);
          late final _SubscriptionAndProduced<V> sap;
          final sub = change.value.listen(
              (e) => _computationListener(sap, change.key, e),
              _changes.addError);
          sap = _SubscriptionAndProduced(sub);
          _changesState[change.key] = sap;
        } else if (change is ChangeRecordUpdate<K, Computed<V>>) {
          final sap = _changesState[change.key]!;
          sap._sub.cancel();
          sap._sub = change.newValue.listen(
              (e) => _computationListener(sap, change.key, e),
              _changes.addError);
        } else if (change is ChangeRecordDelete<K, Computed<V>>) {
          final sap = _changesState[change.key]!;
          sap._sub.cancel();
          _changesState.remove(change.key);
          if (sap._produced) {
            _changes.add({ChangeRecordDelete<K, V>(change.key, null)}.lock);
          }
        } else if (change is ChangeRecordReplace<K, Computed<V>>) {
          _changesState.values.forEach((sap) => sap._sub.cancel());
          _changesState.clear();
          _changes.add(
              <ChangeRecord<K, V>>{ChangeRecordReplace(<K, V>{}.lock)}.lock);
          change.newCollection.forEach((key, value) {
            late final _SubscriptionAndProduced<V> sap;
            final sub = value.listen(
                (e) => _computationListener(sap, key, e), _changes.addError);
            sap = _SubscriptionAndProduced(sub);
            _changesState[key] = sap;
          });
        }
      }
    }

    ComputedSubscription<ISet<ChangeRecord<K, Computed<V>>>>?
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
  Computed<ISet<ChangeRecord<K, V>>> get changes => _changesComputed;

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
    // TODO: we have to use async here because we return a computation,
    //  but the downside is that we are also running the user computation async
    //  we only really want to disable idempotency checks, not really allow async
    final computationComputation = Computed.async(() {
      if (_parent.containsKey(key).use) {
        return _convert(key, _parent[key].use as VParent);
      }
      return null;
    });
    final resultComputation = _keyComputationCache.wrap(key, () {
      final c = computationComputation.use;
      if (c != null) return c.use;
      return null;
    });

    return resultComputation;
  }

  @override
  Computed<ChangeRecord<K, V>> changesFor(K key) {
    // TODO: implement changesFor
    throw UnimplementedError();
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
