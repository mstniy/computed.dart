import 'package:computed/computed.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../icomputedmap.dart';
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
  IComputedMap<K, V> add(K key, V value) =>
      AddComputedMap(this as IComputedMap<K, V>, key, value);

  IComputedMap<K, V> addAll(IMap<K, V> other) =>
      AddAllComputedMap(this as IComputedMap<K, V>, other);

  IComputedMap<K, V> addAllComputed(IComputedMap<K, V> other) =>
      AddAllComputedComputedMap(this as IComputedMap<K, V>, other);

  IComputedMap<RK, RV> cast<RK, RV>() => (this as IComputedMap<K, V>)
      .map((key, value) => MapEntry(key as RK, value as RV));

  IComputedMap<K2, V2> map<K2, V2>(
          MapEntry<K2, V2> Function(K key, V value) convert) =>
      MapComputedMap(this as IComputedMap<K, V>, convert);

  IComputedMap<K2, V2> mapComputed<K2, V2>(
          Computed<Entry<K2, V2>> Function(K key, V value) convert) =>
      MapComputedComputedMap(this as IComputedMap<K, V>, convert);

  IComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V value) convert) =>
      MapValuesComputedMap(this as IComputedMap<K, V>, convert);

  IComputedMap<K, V2> mapValuesComputed<V2>(
          Computed<V2> Function(K key, V value) convert) =>
      MapValuesComputedComputedMap(this as IComputedMap<K, V>, convert);

  IComputedMap<K, V> putIfAbsent(K key, V Function() ifAbsent) =>
      (this as IComputedMap<K, V>).update(key, (v) => v, ifAbsent: ifAbsent);

  IComputedMap<K, V> remove(K key) =>
      RemoveComputedMap(this as IComputedMap<K, V>, key);

  IComputedMap<K, V> removeWhere(bool Function(K key, V value) test) =>
      RemoveWhereComputedMap(this as IComputedMap<K, V>, test);

  IComputedMap<K, V> removeWhereComputed(
          Computed<bool> Function(K key, V value) test) =>
      (this as IComputedMap<K, V>)
          .mapValuesComputed((key, value) {
            final c = test(key, value);
            return $(() => (value, c.use));
          })
          .removeWhere((_, v) => v.$2)
          .mapValues((_, value) => value.$1);

  IComputedMap<K, V> update(K key, V Function(V value) update,
          {V Function()? ifAbsent}) =>
      UpdateComputedMap(this as IComputedMap<K, V>, key, update, ifAbsent);

  IComputedMap<K, V> updateAll(V Function(K key, V value) update) =>
      // This is basically a special case of mapValues where V2==V
      MapValuesComputedMap(this as IComputedMap<K, V>, update);

  IComputedMap<K, V> updateAllComputed(
          Computed<V> Function(K key, V value) update) =>
      // This is basically a special case of mapValuesComputed where V2==V
      MapValuesComputedComputedMap(this as IComputedMap<K, V>, update);

  IComputedMap<K2, IComputedMap<K, V>> groupBy<K2>(
          K2 Function(K key, V value) key) =>
      GroupByComputedMap(this as IComputedMap<K, V>, key);

  IComputedMap<K2, IComputedMap<K, V>> groupByComputed<K2>(
          Computed<K2> Function(K key, V value) key) =>
      (this as IComputedMap<K, V>)
          .mapValuesComputed((k, v) {
            final c = key(k, v);
            return $(() => (c.use, v));
          })
          .groupBy((k, v) => v.$1)
          .mapValues((_, v1) => v1.mapValues((_, v2) => v2.$2));

  IComputedMap<K, (V, V2)> join<V2>(IComputedMap<K, V2> other) =>
      JoinComputedMap(this as IComputedMap<K, V>, other);
  IComputedMap<K, (V, V2?)> lookup<V2>(IComputedMap<K, V2> other) =>
      LookupComputedMap(this as IComputedMap<K, V>, other);
}
