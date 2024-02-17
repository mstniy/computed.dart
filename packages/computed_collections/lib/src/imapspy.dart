import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class IMapSpy<K, V> {
  final IMap<K, V> imap;
  final IMap<K, V> wrapped;
  final ISet<K> changedKeys;

  @override
  int get hashCode => imap.hashCode;

  IMapSpy(this.imap, this.wrapped, this.changedKeys);
  IMapSpy.wrap(this.imap)
      : wrapped = imap,
        changedKeys = ISet();

  V? operator [](K k) {
    return imap[k];
  }

  IMapSpy<K, V> add(K key, V value) {
    return IMapSpy<K, V>(imap.add(key, value), wrapped, changedKeys.add(key));
  }

  IMapSpy<K, V> addAll(IMap<K, V> other, {bool keepOrder = false}) {
    return IMapSpy<K, V>(
        imap.addAll(other), wrapped, changedKeys.addAll(other.keys));
  }

  IMap<K, V> addEntries(Iterable<MapEntry<K, V>> entries) {
    // TODO: implement addEntries
    throw UnimplementedError();
  }

  IMap<K, V> addEntry(MapEntry<K, V> entry) {
    // TODO: implement addEntry
    throw UnimplementedError();
  }

  IMap<K, V> addMap(Map<K, V> map) {
    // TODO: implement addMap
    throw UnimplementedError();
  }

  bool any(bool Function(K key, V value) test) {
    // TODO: implement any
    throw UnimplementedError();
  }

  bool anyEntry(bool Function(MapEntry<K, V> p1) test) {
    // TODO: implement anyEntry
    throw UnimplementedError();
  }

  IMap<RK, RV> cast<RK, RV>() {
    // TODO: implement cast
    throw UnimplementedError();
  }

  IMap<K, V> clear() {
    // TODO: implement clear
    throw UnimplementedError();
  }

  // TODO: implement comparableEntries
  Iterable<Entry<K, V>> get comparableEntries => throw UnimplementedError();

  ConfigMap get config => imap.config;

  bool contains(K key, V value) {
    // TODO: implement contains
    throw UnimplementedError();
  }

  bool containsEntry(MapEntry<K, V> entry) {
    // TODO: implement containsEntry
    throw UnimplementedError();
  }

  bool containsKey(K? key) {
    // TODO: implement containsKey
    throw UnimplementedError();
  }

  bool containsValue(V? value) {
    // TODO: implement containsValue
    throw UnimplementedError();
  }

  // TODO: implement entries
  Iterable<MapEntry<K, V>> get entries => throw UnimplementedError();

  MapEntry<K, V?> entry(K key) {
    // TODO: implement entry
    throw UnimplementedError();
  }

  MapEntry<K, V>? entryOrNull(K key) {
    // TODO: implement entryOrNull
    throw UnimplementedError();
  }

  bool equalItems(covariant Iterable<MapEntry> other) {
    // TODO: implement equalItems
    throw UnimplementedError();
  }

  bool equalItemsAndConfig(IMap other) {
    // TODO: implement equalItemsAndConfig
    throw UnimplementedError();
  }

  bool equalItemsToIMap(IMap other) {
    // TODO: implement equalItemsToIMap
    throw UnimplementedError();
  }

  bool equalItemsToMap(Map other) {
    // TODO: implement equalItemsToMap
    throw UnimplementedError();
  }

  bool everyEntry(bool Function(MapEntry<K, V> p1) test) {
    // TODO: implement everyEntry
    throw UnimplementedError();
  }

  // TODO: implement flush
  IMap<K, V> get flush => throw UnimplementedError();

  void forEach(void Function(K key, V value) f) {
    // TODO: implement forEach
  }

  V? get(K k) {
    // TODO: implement get
    throw UnimplementedError();
  }

  // TODO: implement isDeepEquals
  bool get isDeepEquals => throw UnimplementedError();

  // TODO: implement isEmpty
  bool get isEmpty => throw UnimplementedError();

  // TODO: implement isFlushed
  bool get isFlushed => throw UnimplementedError();

  // TODO: implement isIdentityEquals
  bool get isIdentityEquals => throw UnimplementedError();

  // TODO: implement isNotEmpty
  bool get isNotEmpty => throw UnimplementedError();

  // TODO: implement iterator
  Iterator<MapEntry<K, V>> get iterator => throw UnimplementedError();

  // TODO: implement keys
  Iterable<K> get keys => throw UnimplementedError();

  // TODO: implement length
  int get length => throw UnimplementedError();

  IMap<RK, RV> map<RK, RV>(MapEntry<RK, RV> Function(K key, V value) mapper,
      {bool Function(RK key, RV value)? ifRemove, ConfigMap? config}) {
    // TODO: implement map
    throw UnimplementedError();
  }

  Iterable<T> mapTo<T>(T Function(K key, V value) mapper) {
    // TODO: implement mapTo
    throw UnimplementedError();
  }

  IMap<K, V> putIfAbsent(K key, V Function() ifAbsent,
      {Output<V>? previousValue}) {
    // TODO: implement putIfAbsent
    throw UnimplementedError();
  }

  IMap<K, V> remove(K key) {
    // TODO: implement remove
    throw UnimplementedError();
  }

  IMap<K, V> removeWhere(bool Function(K key, V value) predicate) {
    // TODO: implement removeWhere
    throw UnimplementedError();
  }

  bool same(IMap<K, V> other) {
    // TODO: implement same
    throw UnimplementedError();
  }

  IList<MapEntry<K, V>> toEntryIList(
      {int Function(MapEntry<K, V>? a, MapEntry<K, V>? b)? compare,
      ConfigList? config}) {
    // TODO: implement toEntryIList
    throw UnimplementedError();
  }

  ISet<MapEntry<K, V>> toEntryISet({ConfigSet? config}) {
    // TODO: implement toEntryISet
    throw UnimplementedError();
  }

  List<MapEntry<K, V>> toEntryList(
      {int Function(MapEntry<K, V> a, MapEntry<K, V> b)? compare}) {
    // TODO: implement toEntryList
    throw UnimplementedError();
  }

  Set<MapEntry<K, V>> toEntrySet(
      {int Function(MapEntry<K, V> a, MapEntry<K, V> b)? compare}) {
    // TODO: implement toEntrySet
    throw UnimplementedError();
  }

  Object toJson(
      Object? Function(K p1) toJsonK, Object? Function(V p1) toJsonV) {
    // TODO: implement toJson
    throw UnimplementedError();
  }

  IList<K> toKeyIList({int Function(K? a, K? b)? compare, ConfigList? config}) {
    // TODO: implement toKeyIList
    throw UnimplementedError();
  }

  ISet<K> toKeyISet({ConfigSet? config}) {
    // TODO: implement toKeyISet
    throw UnimplementedError();
  }

  List<K> toKeyList({int Function(K a, K b)? compare}) {
    // TODO: implement toKeyList
    throw UnimplementedError();
  }

  Set<K> toKeySet({int Function(K a, K b)? compare}) {
    // TODO: implement toKeySet
    throw UnimplementedError();
  }

  IList<V> toValueIList(
      {bool sort = false,
      int Function(V a, V b)? compare,
      ConfigList? config}) {
    // TODO: implement toValueIList
    throw UnimplementedError();
  }

  ISet<V> toValueISet({ConfigSet? config}) {
    // TODO: implement toValueISet
    throw UnimplementedError();
  }

  List<V> toValueList({bool sort = false, int Function(V a, V b)? compare}) {
    // TODO: implement toValueList
    throw UnimplementedError();
  }

  Set<V> toValueSet({int Function(V a, V b)? compare}) {
    // TODO: implement toValueSet
    throw UnimplementedError();
  }

  // TODO: implement unlock
  Map<K, V> get unlock => throw UnimplementedError();

  // TODO: implement unlockLazy
  Map<K, V> get unlockLazy => throw UnimplementedError();

  // TODO: implement unlockSorted
  Map<K, V> get unlockSorted => throw UnimplementedError();

  // TODO: implement unlockView
  Map<K, V> get unlockView => throw UnimplementedError();

  IMap<K, V> update(K key, V Function(V value) update,
      {bool Function(K key, V value)? ifRemove,
      V Function()? ifAbsent,
      Output<V>? previousValue}) {
    // TODO: implement update
    throw UnimplementedError();
  }

  IMap<K, V> updateAll(V Function(K key, V value) update,
      {bool Function(K key, V value)? ifRemove}) {
    // TODO: implement updateAll
    throw UnimplementedError();
  }

  // TODO: implement values
  Iterable<V> get values => throw UnimplementedError();

  IMap<K, V> where(bool Function(K key, V value) test) {
    // TODO: implement where
    throw UnimplementedError();
  }

  IMap<K, V> withConfig(ConfigMap config) {
    // TODO: implement withConfig
    throw UnimplementedError();
  }

  IMap<K, V> withConfigFrom(IMap<K, V> other) {
    // TODO: implement withConfigFrom
    throw UnimplementedError();
  }

  // TODO: implement withDeepEquals
  IMap<K, V> get withDeepEquals => throw UnimplementedError();

  // TODO: implement withIdentityEquals
  IMap<K, V> get withIdentityEquals => throw UnimplementedError();

  String toString([bool? prettyPrint]) => imap.toString(prettyPrint);

  // Weird comparison semantics
  bool operator ==(Object other) {
    if (other is IMapSpy<K, V>)
      return (imap == other.imap &&
          identical(wrapped, other.wrapped) &&
          changedKeys == other.changedKeys);
    else if (other is IMap<K, V>) {
      return imap == other;
    } else
      return false;
  }
}
