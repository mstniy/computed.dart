import 'package:computed/computed.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

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
      MapEntry<K2, V2> Function(K key, V Value) convert) {
    // TODO: implement map
    throw UnimplementedError();
  }

  IComputedMap<K2, V2> mapComputed<K2, V2>(
      Computed<MapEntry<K2, V2>> Function(K key, V Value) convert) {
    // TODO: implement mapComputed
    throw UnimplementedError();
  }

  IComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V Value) convert) {
    // TODO: implement mapValues
    throw UnimplementedError();
  }

  IComputedMap<K, V2> mapValuesComputed<V2>(
      Computed<V2> Function(K key, V Value) convert) {
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

  IComputedMap<K, V> updateAll(V Function(K key, V Value) update) {
    // TODO: implement updateAll
    throw UnimplementedError();
  }

  IComputedMap<K, V> updateAllComputed(
      Computed<V> Function(K key, V Value) update) {
    // TODO: implement updateAllComputed
    throw UnimplementedError();
  }
}

class ChildComputedMap<K, V> {
  final IComputedMap<K, V> parent;
  ChildComputedMap(this.parent);

  @visibleForTesting
  // TODO: This is completely wrong semantically. We can't "delegate" mocks this way
  // ignore: invalid_use_of_visible_for_testing_member
  void fix(IMap<K, V> value) => parent.fix(value);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void fixThrow(Object e) => parent.fixThrow(e);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IMap<K, V> Function() mock) => parent.mock(mock);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void unmock() => parent.unmock();
}
