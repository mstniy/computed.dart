import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:meta/meta.dart';

import 'src/cs_computedmap.dart';

/// An in-memory, partially- or fully-observable key-value store.
/// Similar to the ObservableMap from the `observable` package, but with the following upsides:
/// - Individual keys can be observed
/// - Supports immutable snapshots (using fast_immutable_collections)
abstract class IComputedMap<K, V> {
  factory IComputedMap.fromChangeStream(Stream<ChangeEvent<K, V>> stream) {
    return ChangeStreamComputedMap(stream);
  }
  Computed<ChangeEvent<K, V>> get changes;

  @visibleForTesting
  void fix(IMap<K, V> value);

  @visibleForTesting
  void fixThrow(Object e);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IMap<K, V> Function() mock);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void unmock();

  Computed<IMap<K, V>> get snapshot;

  Computed<V?> operator [](K key);

  //IComputedList<MapEntry<K, V>> get entries; // What sort of an interface should IComputedList offer? Strictly from a KV perspective, in-the-middle insertion/deletions are pretty chaotic
  Computed<bool> get isEmpty;
  Computed<bool> get isNotEmpty;
  //IComputedList<K> get keys;
  Computed<int> get length;
  //IComputedList<V> get values;

  IComputedMap<K, V> add(
      K key, V value); // Note that the computed variant is trivial
  IComputedMap<K, V> addAllComputed(IComputedMap<K, V> other);
  IComputedMap<K, V> addAll(IMap<K, V> other);
  //IComputedIMap<K, V> addEntires(IComputedIList<MapEntry<K, V>> newEntries);
  IComputedMap<RK, RV> cast<RK, RV>();
  Computed<bool> containsKey(K key); // Not that the computed variant is trivial
  Computed<bool> containsValue(
      V value); // Not that the computed variant is trivial
  IComputedMap<K2, V2> mapComputed<K2, V2>(
      Computed<MapEntry<K2, V2>> Function(K key, V value) convert);
  IComputedMap<K2, V2> map<K2, V2>(
      MapEntry<K2, V2> Function(K key, V value) convert);
  IComputedMap<K, V2> mapValuesComputed<V2>(
      Computed<V2> Function(K key, V value) convert);
  IComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V value) convert);
  IComputedMap<K, V> putIfAbsent(
      K key, V Function() ifAbsent); // Not that the computed variant is trivial
  IComputedMap<K, V> remove(K key); // Not that the computed variant is trivial
  IComputedMap<K, V> removeWhereComputed(
      Computed<bool> Function(K key, V value) test);
  IComputedMap<K, V> removeWhere(bool Function(K key, V value) test);
  IComputedMap<K, V> update(
      // Note that the computed variant is trivial
      K key,
      V Function(V value) update,
      {V Function()? ifAbsent});
  IComputedMap<K, V> updateAllComputed(
      Computed<V> Function(K key, V value) update);
  IComputedMap<K, V> updateAll(V Function(K key, V value) update);
}
