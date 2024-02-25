import 'package:computed/computed.dart';
import 'package:computed_collections/src/map_values.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../icomputedmap.dart';
import 'add_computedmap.dart';

class ComputedMapMixin<K, V> {
  IComputedMap<K, V> add(K key, V value) =>
      AddComputedMap(this as IComputedMap<K, V>, key, value);

  IComputedMap<K, V> addAll(IMap<K, V> other) {
    // TODO: implement addAll
    throw UnimplementedError();
  }

  IComputedMap<K, V> addAllComputed(IComputedMap<K, V> other) {
    // TODO: implement addAllComputed
    throw UnimplementedError();
  }

  IComputedMap<RK, RV> cast<RK, RV>() {
    // TODO: implement cast
    throw UnimplementedError();
  }

  IComputedMap<K2, V2> map<K2, V2>(
      MapEntry<K2, V2> Function(K key, V value) convert) {
    // TODO: implement map
    throw UnimplementedError();
  }

  IComputedMap<K2, V2> mapComputed<K2, V2>(
      Computed<MapEntry<K2, V2>> Function(K key, V value) convert) {
    // TODO: implement mapComputed
    throw UnimplementedError();
  }

  IComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V value) convert) =>
      MapValuesComputedMap(this as IComputedMap<K, V>, convert);

  IComputedMap<K, V2> mapValuesComputed<V2>(
      Computed<V2> Function(K key, V value) convert) {
    // TODO: implement mapValuesComputed
    throw UnimplementedError();
  }

  IComputedMap<K, V> putIfAbsent(K key, V Function() ifAbsent) {
    // TODO: implement putIfAbsent
    throw UnimplementedError();
  }

  IComputedMap<K, V> remove(K key) {
    // TODO: implement remove
    throw UnimplementedError();
  }

  IComputedMap<K, V> removeWhere(bool Function(K key, V value) test) {
    // TODO: implement removeWhere
    throw UnimplementedError();
  }

  IComputedMap<K, V> removeWhereComputed(
      Computed<bool> Function(K key, V value) test) {
    // TODO: implement removeWhereComputed
    throw UnimplementedError();
  }

  IComputedMap<K, V> update(K key, V Function(V value) update,
      {V Function()? ifAbsent}) {
    // TODO: implement update
    throw UnimplementedError();
  }

  IComputedMap<K, V> updateAll(V Function(K key, V value) update) {
    // TODO: implement updateAll
    throw UnimplementedError();
  }

  IComputedMap<K, V> updateAllComputed(
      Computed<V> Function(K key, V value) update) {
    // TODO: implement updateAllComputed
    throw UnimplementedError();
  }
}
