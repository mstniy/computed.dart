import 'package:computed/computed.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class AddComputedMap<K, V> extends ChildComputedMap<K, V>
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
          .toSet();
      if (changes.isEmpty) throw NoValueException();
      return changes.lock;
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
  IComputedMap<K, V> addAll(IMap<K, V> other) {
    // TODO: implement addAll
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> addAllComputed(IComputedMap<K, V> other) {
    // TODO: implement addAllComputed
    throw UnimplementedError();
  }

  @override
  IComputedMap<RK, RV> cast<RK, RV>() {
    // TODO: implement cast
    throw UnimplementedError();
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
    // TODO: implement containsKey
    throw UnimplementedError();
  }

  @override
  Computed<bool> containsValue(V value) {
    // TODO: implement containsValue
    throw UnimplementedError();
  }

  @override
  // TODO: implement isEmpty
  Computed<bool> get isEmpty => throw UnimplementedError();

  @override
  // TODO: implement isNotEmpty
  Computed<bool> get isNotEmpty => throw UnimplementedError();

  @override
  // TODO: implement length
  Computed<int> get length => throw UnimplementedError();

  @override
  IComputedMap<K2, V2> map<K2, V2>(
      MapEntry<K2, V2> Function(K key, V Value) convert) {
    // TODO: implement map
    throw UnimplementedError();
  }

  @override
  IComputedMap<K2, V2> mapComputed<K2, V2>(
      Computed<MapEntry<K2, V2>> Function(K key, V Value) convert) {
    // TODO: implement mapComputed
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V Value) convert) {
    // TODO: implement mapValues
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V2> mapValuesComputed<V2>(
      Computed<V2> Function(K key, V Value) convert) {
    // TODO: implement mapValuesComputed
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> putIfAbsent(K key, V Function() ifAbsent) {
    // TODO: implement putIfAbsent
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> remove(K key) {
    // TODO: implement remove
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> removeWhere(bool Function(K key, V value) test) {
    // TODO: implement removeWhere
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> removeWhereComputed(
      Computed<bool> Function(K key, V value) test) {
    // TODO: implement removeWhereComputed
    throw UnimplementedError();
  }

  @override
  Computed<IMap<K, V>> get snapshot => _snapshot;

  @override
  IComputedMap<K, V> update(K key, V Function(V value) update,
      {V Function()? ifAbsent}) {
    // TODO: implement update
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> updateAll(V Function(K key, V Value) update) {
    // TODO: implement updateAll
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> updateAllComputed(
      Computed<V> Function(K key, V Value) update) {
    // TODO: implement updateAllComputed
    throw UnimplementedError();
  }
}
