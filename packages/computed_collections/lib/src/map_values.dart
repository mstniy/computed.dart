import 'package:computed/computed.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

class MapValuesComputedMap<K, V, VParent>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final V Function(K key, VParent value) _convert;
  late final Computed<ISet<ChangeRecord<K, V>>> _changes;
  late final Computed<IMap<K, V>> _snapshot;

  MapValuesComputedMap(this._parent, this._convert) {
    _changes = Computed(() {
      final changes = _parent.changes.use.map((upstreamChange) {
        if (upstreamChange is ChangeRecordInsert<K, VParent>) {
          return ChangeRecordInsert(upstreamChange.key,
              _convert(upstreamChange.key, upstreamChange.value));
        } else if (upstreamChange is ChangeRecordUpdate<K, VParent>) {
          return ChangeRecordUpdate<K, V>(upstreamChange.key, null,
              _convert(upstreamChange.key, upstreamChange.newValue));
        } else if (upstreamChange is ChangeRecordDelete<K, VParent>) {
          return ChangeRecordDelete<K, V>(upstreamChange.key, null);
        } else if (upstreamChange is ChangeRecordReplace<K, VParent>) {
          return ChangeRecordReplace(upstreamChange.newCollection
              .map(((key, value) => MapEntry(key, _convert(key, value)))));
        } else {
          throw TypeError();
        }
      }).toISet();
      if (changes.isEmpty) throw NoValueException();
      return changes;
    });
    // TODO: asStream introduces a lag of one microtask here
    //  Can we change it to make the api more uniform?
    _snapshot = ChangeStreamComputedMap(
            _changes.asStream,
            () => _parent.snapshot.use
                .map(((key, value) => MapEntry(key, _convert(key, value)))))
        .snapshot;
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
  Computed<V?> operator [](K key) => $(() {
        if (_parent.containsKey(key).use) {
          return _convert(key, _parent[key].use as VParent);
        }
        return null;
      });

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
