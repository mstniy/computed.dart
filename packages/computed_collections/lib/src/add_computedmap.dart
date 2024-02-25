import 'package:computed/computed.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class AddComputedMap<K, V>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  K _key;
  V _value;
  final IComputedMap<K, V> _parent;
  late final Computed<ISet<ChangeRecord<K, V>>> _changes;
  late final Computed<IMap<K, V>> _snapshot;
  AddComputedMap(this._parent, this._key, this._value) {
    _snapshot = $(() => _parent.snapshot.use.add(this._key, this._value));
    _changes = Computed(() {
      final changes = _parent.changes.use
          .map((upstreamChange) {
            if (upstreamChange is ChangeRecordInsert<K, V>) {
              if (upstreamChange.key == _key) return <ChangeRecord<K, V>>[];
              return [upstreamChange];
            } else if (upstreamChange is ChangeRecordUpdate<K, V>) {
              if (upstreamChange.key == _key) return <ChangeRecord<K, V>>[];
              return [upstreamChange];
            } else if (upstreamChange is ChangeRecordDelete<K, V>) {
              if (upstreamChange.key == _key) return <ChangeRecord<K, V>>[];
              return [upstreamChange];
            } else if (upstreamChange is ChangeRecordReplace<K, V>) {
              return [
                ChangeRecordReplace(
                    upstreamChange.newCollection.add(_key, _value))
              ];
            } else {
              assert(false);
              return <ChangeRecord<K, V>>[];
            }
          })
          .expand((e) => e)
          .toISet();
      if (changes.isEmpty) throw NoValueException();
      return changes;
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
  Computed<ISet<ChangeRecord<K, V>>> get changes => _changes;

  @override
  Computed<ChangeRecord<K, V>> changesFor(K key) {
    // The value of _key never changes
    if (key == _key) return $(() => throw NoValueException);
    return _parent.changesFor(key);
  }

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
