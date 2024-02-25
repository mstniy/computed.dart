import 'package:computed/computed.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

class MapValuesComputedComputedMap<K, V, VParent>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final Computed<V> Function(K key, VParent value) _convert;
  late final Computed<ISet<ChangeRecord<K, V>>> _changes;
  late final Computed<IMap<K, V>> _snapshot;

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
    _changes = $(() {
      // TODO: We need .react here, but we can't .react on computations
      //  This might break things when we eg. get unmocked
      var gotNVE = false;
      final unwrapped = _computedChanges.use
          .map((record) {
            try {
              if (record is ChangeRecordInsert<K, Computed<V>>) {
                return [ChangeRecordInsert(record.key, record.value.use)];
              } else if (record is ChangeRecordUpdate<K, Computed<V>>) {
                return [
                  ChangeRecordUpdate<K, V>(
                      record.key, null, record.newValue.use)
                ];
              } else if (record is ChangeRecordDelete<K, Computed<V>>) {
                return [ChangeRecordDelete<K, V>(record.key, null)];
              } else if (record is ChangeRecordReplace<K, Computed<V>>) {
                return [
                  ChangeRecordReplace(record.newCollection
                      .map(((key, value) => MapEntry(key, value.use))))
                ];
              } else {
                throw TypeError();
              }
            } on NoValueException {
              gotNVE = true;
              return <ChangeRecord<K, V>>[];
              // Keep going, we want Computed to be aware of all the dependencies
            }
          })
          .expand((e) => e)
          .toISet();
      if (gotNVE) throw NoValueException();
      return unwrapped;
    });
    // TODO: asStream introduces a lag of one microtask here
    //  Can we change it to make the api more uniform?
    _snapshot = ChangeStreamComputedMap(_changes.asStream, () {
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
  Computed<ISet<ChangeRecord<K, V>>> get changes => _changes;

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
  // TODO: cache the result, like ChangeStreamComputedMap
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
    final resultComputation = $(() {
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
