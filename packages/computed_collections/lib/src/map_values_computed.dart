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
  final _changesState = <K, ComputedSubscription<V>>{};
  late final Computed<IMap<K, V>> _snapshot;
  final _keyComputationCache = ComputationCache<K, V?>();
  final V _noValueSentinel;

  MapValuesComputedComputedMap(
      this._parent, this._convert, this._noValueSentinel) {
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

    void _computationListener(K key, V value) {
      _changes.add(KeyChanges({key: ChangeRecordUpdate<V>(value)}.lock));
    }

    void _computedChangesListener(ChangeEvent<K, Computed<V>> computedChanges) {
      if (computedChanges is ChangeEventReplace<K, Computed<V>>) {
        _changesState.values.forEach((sub) => sub.cancel());
        _changesState.clear();
        _changes.add(ChangeEventReplace(computedChanges.newCollection
            .map((key, value) => MapEntry(key, _noValueSentinel))));
        computedChanges.newCollection.forEach((key, value) {
          final sub = value.listen(
              (e) => _computationListener(key, e), _changes.addError);
          _changesState[key] = sub;
        });
      } else if (computedChanges is KeyChanges<K, Computed<V>>) {
        for (var e in computedChanges.changes.entries) {
          final key = e.key;
          final change = e.value;
          if (change is ChangeRecordInsert<Computed<V>>) {
            assert(_changesState[key] == null);
            final sub = change.value
                .listen((e) => _computationListener(key, e), _changes.addError);
            _changesState[key] = sub;
            _changes.add(KeyChanges(
                {key: ChangeRecordInsert<V>(_noValueSentinel)}.lock));
          } else if (change is ChangeRecordUpdate<Computed<V>>) {
            final sub = _changesState[key]!;
            sub.cancel();
            _changesState[key] = change.newValue
                .listen((e) => _computationListener(key, e), _changes.addError);
            _changes.add(KeyChanges(
                {key: ChangeRecordUpdate<V>(_noValueSentinel)}.lock));
          } else if (change is ChangeRecordDelete<Computed<V>>) {
            final sub = _changesState.remove(key)!;
            sub.cancel();
            _changes.add(KeyChanges({key: ChangeRecordDelete<V>()}.lock));
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
      if (c != null) return c.useOr(_noValueSentinel);
      return null;
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
