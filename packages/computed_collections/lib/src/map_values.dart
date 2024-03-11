import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

class MapValuesComputedMap<K, V, VParent>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final V Function(K key, VParent value) _convert;
  late final Computed<ChangeEvent<K, V>> _changes;
  late final Computed<IMap<K, V>> _snapshot;
  final _keyComputationCache = ComputationCache<K, V?>();

  MapValuesComputedMap(this._parent, this._convert) {
    _changes = Computed(() {
      // TODO: make this a stream map instead? does it have laziness?
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
            return MapEntry(key,
                ChangeRecordUpdate<V>(_convert(key, upstreamChange.newValue)));
          } else if (upstreamChange is ChangeRecordDelete<VParent>) {
            return MapEntry(key, ChangeRecordDelete<V>());
          } else {
            throw TypeError();
          }
        })));
      } else {
        throw TypeError();
      }
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
  Computed<ChangeEvent<K, V>> get changes => _changes;

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
  Computed<V?> operator [](K key) => _keyComputationCache.wrap(key, () {
        if (_parent.containsKey(key).use) {
          return _convert(key, _parent[key].use as VParent);
        }
        return null;
      });

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
