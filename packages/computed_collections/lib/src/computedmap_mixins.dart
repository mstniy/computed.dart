import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/src/const_computedmap.dart';
import 'package:computed_collections/src/group_by.dart';
import 'package:computed_collections/src/map_values.dart';
import 'package:computed_collections/src/map_values_computed.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

import '../change_event.dart';
import '../icomputedmap.dart';
import 'add_computedmap.dart';

mixin OperatorsMixin<K, V> {
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
          Computed<V2> Function(K key, V value) convert) =>
      MapValuesComputedComputedMap(this as IComputedMap<K, V>, convert);

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

  IComputedMap<K2, IComputedMap<K, V>> groupBy<K2>(
          K2 Function(K key, V value) key) =>
      GroupByComputedMap(this as IComputedMap<K, V>, key);

  IComputedMap<K2, IComputedMap<K, V>> groupByComputed<K2>(
      Computed<K2> Function(K key, V value) key) {
    // TODO: implement groupByComputed
    throw UnimplementedError();
  }
}

mixin MockMixin<K, V> {
  Computed<ChangeEvent<K, V>> get changes;
  Computed<IMap<K, V>> get snapshot;
  Computed<int> get length;
  Computed<bool> get isEmpty;
  Computed<bool> get isNotEmpty;
  ComputationCache<K, V?> get keyComputations;
  ComputationCache<K, bool> get containsKeyComputations;
  ComputationCache<V, bool> get containsValueComputations;

  @visibleForTesting
  void fix(IMap<K, V> value) => mock(ConstComputedMap(value));

  @visibleForTesting
  void fixThrow(Object e) {
    for (var c in [changes, snapshot, isEmpty, isNotEmpty, length]) {
      // ignore: invalid_use_of_visible_for_testing_member
      c.fixThrow(e);
    }
    for (var cc in [
      keyComputations,
      containsKeyComputations,
      containsValueComputations
    ]) {
      // ignore: invalid_use_of_visible_for_testing_member
      cc.mock((key) => throw e);
    }
  }

  @visibleForTesting
  void mock(IComputedMap<K, V> mock) {
    // TODO: The changes should always initially emit a replacement to the upstream snapshot, even if the upstream already has a change
    //  This is better expressed through .react-ing to computations, which we do not have yet.
    changes
        // ignore: invalid_use_of_visible_for_testing_member
        .mock(() => mock.changes.useOr(ChangeEventReplace(mock.snapshot.use)));
    // ignore: invalid_use_of_visible_for_testing_member
    snapshot.mock(() => mock.snapshot.use);
    // ignore: invalid_use_of_visible_for_testing_member
    keyComputations.mock((key) => mock[key].use);
    // Note that this pattern (of calling functions that return computations and `use`ing their results)
    // inside another computation) assumes that they will always return the exact same computation
    // for long as there is a listener (note that `ComputationCache` satisfies this).
    // ignore: invalid_use_of_visible_for_testing_member
    containsKeyComputations.mock((key) => mock.containsKey(key).use);
    // ignore: invalid_use_of_visible_for_testing_member
    containsValueComputations.mock((v) => mock.containsValue(v).use);
    // ignore: invalid_use_of_visible_for_testing_member
    isEmpty.mock(() => mock.isEmpty.use);
    // ignore: invalid_use_of_visible_for_testing_member
    isNotEmpty.mock(() => mock.isNotEmpty.use);
    // ignore: invalid_use_of_visible_for_testing_member
    length.mock(() => mock.length.use);
  }

  @visibleForTesting
  void unmock() {
    for (var c in [changes, snapshot, isEmpty, isNotEmpty, length]) {
      // ignore: invalid_use_of_visible_for_testing_member
      c.unmock();
    }
    for (var cc in [
      keyComputations,
      containsKeyComputations,
      containsValueComputations
    ]) {
      // ignore: invalid_use_of_visible_for_testing_member
      cc.unmock();
    }
  }
}
