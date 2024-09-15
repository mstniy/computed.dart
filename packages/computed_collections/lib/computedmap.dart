import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/src/const.dart';
import 'package:computed_collections/src/flat.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'src/cs.dart';
import 'src/ss.dart';

/// An in-memory, partially- or fully-observable key-value store.
/// Similar to the ObservableMap from the `observable` package, but with the following upsides:
/// - Individual keys can be observed
/// - Supports immutable snapshots (using fast_immutable_collections)
abstract class ComputedMap<K, V> {
  factory ComputedMap.fromIMap(IMap<K, V> m) => ConstComputedMap(m);
  factory ComputedMap.fromChangeStream(Computed<ChangeEvent<K, V>> stream) =>
      ChangeStreamComputedMap(stream);
  factory ComputedMap.fromSnapshotStream(Computed<IMap<K, V>> stream) =>
      SnapshotStreamComputedMap(stream);
  Computed<ChangeEvent<K, V>> get changes;

  Computed<IMap<K, V>> get snapshot;

  Computed<V?> operator [](K key);

  //IComputedList<MapEntry<K, V>> get entries; // What sort of an interface should IComputedList offer? Strictly from a KV perspective, in-the-middle insertion/deletions are pretty chaotic
  Computed<bool> get isEmpty;
  Computed<bool> get isNotEmpty;
  //IComputedList<K> get keys;
  Computed<int> get length;
  //IComputedList<V> get values;

  ComputedMap<K, V> add(
      K key, V value); // Note that the computed variant is trivial
  ComputedMap<K, V> addAllComputed(ComputedMap<K, V> other);
  ComputedMap<K, V> addAll(IMap<K, V> other);
  //IComputedIMap<K, V> addEntires(IComputedIList<MapEntry<K, V>> newEntries);
  ComputedMap<RK, RV> cast<RK, RV>();
  Computed<bool> containsKey(K key); // Not that the computed variant is trivial
  Computed<bool> containsValue(
      V value); // Not that the computed variant is trivial
  ComputedMap<K2, V2> mapComputed<K2, V2>(
      Computed<Entry<K2, V2>> Function(K key, V value) convert);
  ComputedMap<K2, V2> map<K2, V2>(
      MapEntry<K2, V2> Function(K key, V value) convert);
  ComputedMap<K, V2> mapValuesComputed<V2>(
      Computed<V2> Function(K key, V value) convert);
  ComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V value) convert);
  ComputedMap<K, V> putIfAbsent(
      K key, V Function() ifAbsent); // Not that the computed variant is trivial
  ComputedMap<K, V> remove(K key); // Not that the computed variant is trivial
  ComputedMap<K, V> removeWhereComputed(
      Computed<bool> Function(K key, V value) test);
  ComputedMap<K, V> removeWhere(bool Function(K key, V value) test);
  ComputedMap<K, V> update(
      // Note that the computed variant is trivial
      K key,
      V Function(V value) update,
      {V Function()? ifAbsent});
  ComputedMap<K, V> updateAllComputed(
      Computed<V> Function(K key, V value) update);
  ComputedMap<K, V> updateAll(V Function(K key, V value) update);

  ComputedMap<K2, ComputedMap<K, V>> groupBy<K2>(
      K2 Function(K key, V value) key);
  ComputedMap<K2, ComputedMap<K, V>> groupByComputed<K2>(
      Computed<K2> Function(K key, V value) key);

  ComputedMap<K, (V, V2)> join<V2>(ComputedMap<K, V2> other);
  ComputedMap<K, (V, V2?)> lookup<V2>(ComputedMap<K, V2> other);

  ComputedMap<(K, K2), (V, V2)> cartesianProduct<K2, V2>(
      ComputedMap<K2, V2> other);
}

extension ComputedComputedFlat<K1, K2, V>
    on ComputedMap<K1, ComputedMap<K2, V>> {
  ComputedMap<(K1, K2), V> flat() => FlatComputedMap(this);
}
