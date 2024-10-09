import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/src/const.dart';
import 'package:computed_collections/src/flat.dart';
import 'package:computed_collections/src/piecewise.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'src/cs.dart';
import 'src/cs_with_prev.dart';
import 'src/ss.dart';

/// An in-memory, partially- or fully-observable key-value store.
///
/// Similar to the ObservableMap from the observable package, but with the following upsides:
/// - Individual keys can be observed in an asymptotically optimal manner.
/// - Has value semantics thanks to immutability (using fast_immutable_collections).
/// - Supports reactive operations consuming and emitting [ComputedMap]s.
abstract class ComputedMap<K, V> {
  /// Constructs a constant [ComputedMap] from a given [IMap].
  factory ComputedMap.fromIMap(IMap<K, V> m) => ConstComputedMap(m);

  /// Constructs a [ComputedMap] that tracks [stream]. Initialized to the empty map.
  factory ComputedMap.fromChangeStream(Computed<ChangeEvent<K, V>> stream) =>
      ChangeStreamComputedMap(stream);

  /// Like [ComputedMap.fromChangeStream], but lets the change stream computation depend on the snapshot of the map.
  factory ComputedMap.fromChangeStreamWithPrev(
          ChangeEvent<K, V> Function(IMap<K, V>?) f) =>
      ChangeStreamWithPrevComputedMap(f);

  /// Constructs a [ComputedMap] from the given snapshot stream.
  ///
  /// The returned map internally computes a change stream by comparing
  /// each new snapshot to the previous one.
  factory ComputedMap.fromSnapshotStream(Computed<IMap<K, V>> stream) =>
      SnapshotStreamComputedMap(stream);

  /// Constructs a constant [ComputedMap] defined by [f] over the key domain [domain].
  ///
  /// The main advantage over [ComputedMap.fromIMap] is that only the reactively
  /// used keys are computed.
  ///
  /// Make sure either:
  ///   - [domain] is finite or
  ///   - [snapshot] is never used.
  factory ComputedMap.fromPiecewise(Iterable<K> domain, V Function(K key) f) =>
      PiecewiseComputedMap(domain, f);

  /// Like .fromPiecewise, but the values are defined by reactive computations.
  factory ComputedMap.fromPiecewiseComputed(
          Iterable<K> domain, Computed<V> Function(K key) f) =>
      ComputedMap.fromPiecewise(domain, f).mapValuesComputed((_, c) => c);

  /// A computation representing the last change event on this map.
  Computed<ChangeEvent<K, V>> get changes;

  /// A computation representing the snapshot of this map.
  Computed<IMap<K, V>> get snapshot;

  /// Returns a computation representing the given key of this map.
  Computed<V?> operator [](K key);

  /// A computation representing the emptyness of this map.
  Computed<bool> get isEmpty;

  /// Opposite of [isEmpty].
  Computed<bool> get isNotEmpty;

  /// A computation representing the length of this map.
  Computed<int> get length;

  /// Reactively adds the pair [key], [value] to this reactive map.
  ComputedMap<K, V> add(
      K key, V value); // Note that the computed variant is trivial

  /// Reactively adds [other] to this reactive map.
  ComputedMap<K, V> addAllComputed(ComputedMap<K, V> other);

  /// Reactively adds [other] to this reactive map.
  ComputedMap<K, V> addAll(IMap<K, V> other);

  /// Reactively casts the entries of this reactive map.
  ComputedMap<RK, RV> cast<RK, RV>();

  /// Returns a computation representing if this reactive map contains [key].
  Computed<bool> containsKey(K key); // Not that the computed variant is trivial

  /// Returns a computation representing if this reactive map contains [value].
  Computed<bool> containsValue(
      V value); // Not that the computed variant is trivial

  /// Reactively maps each entry of this reactive map by [convert].
  ComputedMap<K2, V2> mapComputed<K2, V2>(
      Computed<Entry<K2, V2>> Function(K key, V value) convert);

  /// Reactively maps each entry of this reactive map by [convert].
  ComputedMap<K2, V2> map<K2, V2>(
      MapEntry<K2, V2> Function(K key, V value) convert);

  /// Reactively maps all values of this reactive map by [convert].
  ComputedMap<K, V2> mapValuesComputed<V2>(
      Computed<V2> Function(K key, V value) convert);

  /// Reactively maps all values of this reactive map by [convert].
  ComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V value) convert);

  /// Reactively adds [key] to this reactive map using the value returned by [ifAbsent], if [key] does not already exist.
  ComputedMap<K, V> putIfAbsent(
      K key, V Function() ifAbsent); // Not that the computed variant is trivial

  /// Reactively removes [key] from this reactive map.
  ComputedMap<K, V> remove(K key); // Not that the computed variant is trivial

  /// Reactively removes all entries satisfying [test] from this reactive map.
  ComputedMap<K, V> removeWhereComputed(
      Computed<bool> Function(K key, V value) test);

  /// Reactively removes all entries satisfying [test] from this reactive map.
  ComputedMap<K, V> removeWhere(bool Function(K key, V value) test);

  /// Reactively updates the value for [key].
  ///
  /// Uses [ifAbsent] if [key] does not already exist.
  ComputedMap<K, V> update(
      // Note that the computed variant is trivial
      K key,
      V Function(V value) update,
      {V Function()? ifAbsent});

  /// A special case of [mapValuesComputed] where the input and output types are the same.
  ComputedMap<K, V> updateAllComputed(
      Computed<V> Function(K key, V value) update);

  /// A special case of [mapValues] where the input and output types are the same.
  ComputedMap<K, V> updateAll(V Function(K key, V value) update);

  /// Groups this map using the given key function as a [ComputedMap].
  ///
  /// The outer key is set to the result of the key function. The inner
  /// key is set to the original key.
  ComputedMap<K2, ComputedMap<K, V>> groupBy<K2>(
      K2 Function(K key, V value) key);

  /// As with [groupBy], but groups the elements by the reactive value of a computation.
  ComputedMap<K2, ComputedMap<K, V>> groupByComputed<K2>(
      Computed<K2> Function(K key, V value) key);

  /// Returns the inner join of this with [other] as a [ComputedMap].
  ///
  /// The returned map only has the keys which exist on both this map and [other].
  /// The values are records containing the corresponding values from both maps.
  ComputedMap<K, (V, V2)> join<V2>(ComputedMap<K, V2> other);

  /// Returns the left join of this [ComputedMap] with [other] as a [ComputedMap].
  ///
  /// The returned map has the same set of keys as this.
  /// The values are records containing the corresponding values from both maps,
  /// and null, if the key does not exist on [other].
  ComputedMap<K, (V, V2?)> lookup<V2>(ComputedMap<K, V2> other);

  /// Returns the cartesian product of this [ComputedMap] with [other] as a [ComputedMap].
  ///
  /// The returned map has all the key combinations of this [ComputedMap] with [other].
  /// The values are records containing the corresponding values from both maps.
  ComputedMap<(K, K2), (V, V2)> cartesianProduct<K2, V2>(
      ComputedMap<K2, V2> other);
}

extension ComputedComputedFlat<K1, K2, V>
    on ComputedMap<K1, ComputedMap<K2, V>> {
  /// Returns a flattened version of this nested map as a [ComputedMap].
  ///
  /// The keys are records containing keys from both the outer and
  /// the corresponding inner maps.
  /// Similar to [Iterable.expand].
  ComputedMap<(K1, K2), V> flat() => FlatComputedMap(this);
}
