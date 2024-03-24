import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class AddComputedMap<K, V>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  K _key;
  V _value;
  final IComputedMap<K, V> _parent;
  late final Computed<ChangeEvent<K, V>> _changes;
  late final Computed<IMap<K, V>> _snapshot;
  AddComputedMap(this._parent, this._key, this._value) {
    _snapshot = $(() => _parent.snapshot.use.add(this._key, this._value));
    _changes = Computed(() {
      final changeEvent = _parent.changes.use;
      switch (changeEvent) {
        case ChangeEventReplace<K, V>():
          return ChangeEventReplace(
              changeEvent.newCollection.add(_key, _value));
        case KeyChanges<K, V>():
          final changes = changeEvent.changes.entries.map((upstreamChange) {
            if (upstreamChange.key == _key) {
              return <MapEntry<K, ChangeRecord<V>>>[];
            }
            return [upstreamChange];
          }).expand((e) => e);
          if (changes.isEmpty) throw NoValueException();
          return KeyChanges(IMap.fromEntries(changes));
      }
    });
  }

  Computed<V?> operator [](K key) {
    if (key == _key) return $(() => _value);
    return _parent[key];
  }

  @override
  IComputedMap<K, V> add(K key, V value) {
    if (key == _key) {
      return AddComputedMap(_parent, key, value);
    } else {
      return AddComputedMap(this, key, value);
    }
  }

  @override
  Computed<ChangeEvent<K, V>> get changes => _changes;

  @override
  Computed<bool> containsKey(K key) {
    if (key == _key) return $(() => true);
    return _parent.containsKey(key);
  }

  @override
  Computed<bool> containsValue(V value) {
    if (value == _value) return $(() => true);
    return _parent.containsValue(value);
  }

  @override
  Computed<bool> get isEmpty => $(() => false);

  @override
  Computed<bool> get isNotEmpty => $(() => true);

  @override
  Computed<int> get length =>
      $(() => _parent.length.use + (_parent.containsKey(_key).use ? 0 : 1));

  @override
  Computed<IMap<K, V>> get snapshot => _snapshot;

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
