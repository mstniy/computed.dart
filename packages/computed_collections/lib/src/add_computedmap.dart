import 'package:computed/computed.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class AddComputedMap<K, V> extends ChildComputedMap<K, V>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  K _key;
  V _value;
  late final Computed<ISet<ChangeRecord<K, V>>> _changes;
  late final Computed<IMap<K, V>> _snapshot;
  AddComputedMap(IComputedMap<K, V> _parent, this._key, this._value)
      : super(_parent) {
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
    return parent[key];
  }

  @override
  IComputedMap<K, V> add(K key, V value) {
    if (key == _key) {
      return AddComputedMap(parent, key, value);
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
    return parent.changesFor(key);
  }

  @override
  Computed<bool> containsKey(K key) {
    if (key == _key) return $(() => true);
    return parent.containsKey(key);
  }

  @override
  Computed<bool> containsValue(V value) {
    if (value == _value) return $(() => true);
    return parent.containsValue(value);
  }

  @override
  Computed<bool> get isEmpty => $(() => false);

  @override
  Computed<bool> get isNotEmpty => $(() => true);

  @override
  Computed<int> get length =>
      $(() => parent.length.use + (parent.containsKey(_key).use ? 0 : 1));

  @override
  Computed<IMap<K, V>> get snapshot => _snapshot;
}
