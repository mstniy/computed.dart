import 'package:computed/computed.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../computedmap.dart';
import 'add_all_computed.dart';
import 'group_by.dart';
import 'map.dart';
import 'map_computed.dart';
import 'map_values.dart';
import 'map_values_computed.dart';
import 'remove.dart';
import 'remove_where.dart';
import 'add_all.dart';
import 'add_computedmap.dart';
import 'update.dart';
import 'join.dart';
import 'lookup.dart';

mixin OperatorsMixin<K, V> {
  ComputedMap<K, V> add(K key, V value) =>
      AddComputedMap(this as ComputedMap<K, V>, key, value);

  ComputedMap<K, V> addAll(IMap<K, V> other) =>
      AddAllComputedMap(this as ComputedMap<K, V>, other);

  ComputedMap<K, V> addAllComputed(ComputedMap<K, V> other) =>
      AddAllComputedComputedMap(this as ComputedMap<K, V>, other);

  ComputedMap<RK, RV> cast<RK, RV>() => (this as ComputedMap<K, V>)
      .map((key, value) => MapEntry(key as RK, value as RV));

  ComputedMap<K2, V2> map<K2, V2>(
          MapEntry<K2, V2> Function(K key, V value) convert) =>
      MapComputedMap(this as ComputedMap<K, V>, convert);

  ComputedMap<K2, V2> mapComputed<K2, V2>(
          Computed<Entry<K2, V2>> Function(K key, V value) convert) =>
      MapComputedComputedMap(this as ComputedMap<K, V>, convert);

  ComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V value) convert) =>
      MapValuesComputedMap(this as ComputedMap<K, V>, convert);

  ComputedMap<K, V2> mapValuesComputed<V2>(
          Computed<V2> Function(K key, V value) convert) =>
      MapValuesComputedComputedMap(this as ComputedMap<K, V>, convert);

  ComputedMap<K, V> putIfAbsent(K key, V Function() ifAbsent) =>
      (this as ComputedMap<K, V>).update(key, (v) => v, ifAbsent: ifAbsent);

  ComputedMap<K, V> remove(K key) =>
      RemoveComputedMap(this as ComputedMap<K, V>, key);

  ComputedMap<K, V> removeWhere(bool Function(K key, V value) test) =>
      RemoveWhereComputedMap(this as ComputedMap<K, V>, test);

  ComputedMap<K, V> removeWhereComputed(
          Computed<bool> Function(K key, V value) test) =>
      (this as ComputedMap<K, V>)
          .mapValuesComputed((key, value) {
            final c = test(key, value);
            return $(() => (value, c.use));
          })
          .removeWhere((_, v) => v.$2)
          .mapValues((_, value) => value.$1);

  ComputedMap<K, V> update(K key, V Function(V value) update,
          {V Function()? ifAbsent}) =>
      UpdateComputedMap(this as ComputedMap<K, V>, key, update, ifAbsent);

  ComputedMap<K, V> updateAll(V Function(K key, V value) update) =>
      // This is basically a special case of mapValues where V2==V
      MapValuesComputedMap(this as ComputedMap<K, V>, update);

  ComputedMap<K, V> updateAllComputed(
          Computed<V> Function(K key, V value) update) =>
      // This is basically a special case of mapValuesComputed where V2==V
      MapValuesComputedComputedMap(this as ComputedMap<K, V>, update);

  ComputedMap<K2, ComputedMap<K, V>> groupBy<K2>(
          K2 Function(K key, V value) key) =>
      GroupByComputedMap(this as ComputedMap<K, V>, key);

  ComputedMap<K2, ComputedMap<K, V>> groupByComputed<K2>(
          Computed<K2> Function(K key, V value) key) =>
      (this as ComputedMap<K, V>)
          .mapValuesComputed((k, v) {
            final c = key(k, v);
            return $(() => (c.use, v));
          })
          .groupBy((k, v) => v.$1)
          .mapValues((_, v1) => v1.mapValues((_, v2) => v2.$2));

  ComputedMap<K, (V, V2)> join<V2>(ComputedMap<K, V2> other) =>
      JoinComputedMap(this as ComputedMap<K, V>, other);
  ComputedMap<K, (V, V2?)> lookup<V2>(ComputedMap<K, V2> other) =>
      LookupComputedMap(this as ComputedMap<K, V>, other);
}
