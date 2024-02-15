import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class IMapSpy<K, V> implements IMap<K, V> {
  final IMap<K, V> _imap;
  final IMap<K, V> wrapped;
  final ISet<K> changedKeys;

  IMapSpy(this._imap, this.wrapped, this.changedKeys);
  IMapSpy.wrap(this._imap)
      : wrapped = _imap,
        changedKeys = ISet();

  @override
  V? operator [](K k) {
    return _imap[k];
  }

  @override
  IMap<K, V> add(K key, V value) {
    return IMapSpy<K, V>(_imap.add(key, value), wrapped, changedKeys.add(key));
  }

  @override
  IMap<K, V> addAll(IMap<K, V> imap, {bool keepOrder = false}) {
    return IMapSpy<K, V>(
        _imap.addAll(imap), wrapped, changedKeys.addAll(imap.keys));
  }

  @override
  IMap<K, V> addEntries(Iterable<MapEntry<K, V>> entries) {
    // TODO: implement addEntries
    throw UnimplementedError();
  }

  @override
  IMap<K, V> addEntry(MapEntry<K, V> entry) {
    // TODO: implement addEntry
    throw UnimplementedError();
  }

  @override
  IMap<K, V> addMap(Map<K, V> map) {
    // TODO: implement addMap
    throw UnimplementedError();
  }

  @override
  bool any(bool Function(K key, V value) test) {
    // TODO: implement any
    throw UnimplementedError();
  }

  @override
  bool anyEntry(bool Function(MapEntry<K, V> p1) test) {
    // TODO: implement anyEntry
    throw UnimplementedError();
  }

  @override
  IMap<RK, RV> cast<RK, RV>() {
    // TODO: implement cast
    throw UnimplementedError();
  }

  @override
  IMap<K, V> clear() {
    // TODO: implement clear
    throw UnimplementedError();
  }

  @override
  // TODO: implement comparableEntries
  Iterable<Entry<K, V>> get comparableEntries => throw UnimplementedError();

  @override
  // TODO: implement config
  ConfigMap get config => throw UnimplementedError();

  @override
  bool contains(K key, V value) {
    // TODO: implement contains
    throw UnimplementedError();
  }

  @override
  bool containsEntry(MapEntry<K, V> entry) {
    // TODO: implement containsEntry
    throw UnimplementedError();
  }

  @override
  bool containsKey(K? key) {
    // TODO: implement containsKey
    throw UnimplementedError();
  }

  @override
  bool containsValue(V? value) {
    // TODO: implement containsValue
    throw UnimplementedError();
  }

  @override
  // TODO: implement entries
  Iterable<MapEntry<K, V>> get entries => throw UnimplementedError();

  @override
  MapEntry<K, V?> entry(K key) {
    // TODO: implement entry
    throw UnimplementedError();
  }

  @override
  MapEntry<K, V>? entryOrNull(K key) {
    // TODO: implement entryOrNull
    throw UnimplementedError();
  }

  @override
  bool equalItems(covariant Iterable<MapEntry> other) {
    // TODO: implement equalItems
    throw UnimplementedError();
  }

  @override
  bool equalItemsAndConfig(IMap other) {
    // TODO: implement equalItemsAndConfig
    throw UnimplementedError();
  }

  @override
  bool equalItemsToIMap(IMap other) {
    // TODO: implement equalItemsToIMap
    throw UnimplementedError();
  }

  @override
  bool equalItemsToMap(Map other) {
    // TODO: implement equalItemsToMap
    throw UnimplementedError();
  }

  @override
  bool everyEntry(bool Function(MapEntry<K, V> p1) test) {
    // TODO: implement everyEntry
    throw UnimplementedError();
  }

  @override
  // TODO: implement flush
  IMap<K, V> get flush => throw UnimplementedError();

  @override
  void forEach(void Function(K key, V value) f) {
    // TODO: implement forEach
  }

  @override
  V? get(K k) {
    // TODO: implement get
    throw UnimplementedError();
  }

  @override
  // TODO: implement isDeepEquals
  bool get isDeepEquals => throw UnimplementedError();

  @override
  // TODO: implement isEmpty
  bool get isEmpty => throw UnimplementedError();

  @override
  // TODO: implement isFlushed
  bool get isFlushed => throw UnimplementedError();

  @override
  // TODO: implement isIdentityEquals
  bool get isIdentityEquals => throw UnimplementedError();

  @override
  // TODO: implement isNotEmpty
  bool get isNotEmpty => throw UnimplementedError();

  @override
  // TODO: implement iterator
  Iterator<MapEntry<K, V>> get iterator => throw UnimplementedError();

  @override
  // TODO: implement keys
  Iterable<K> get keys => throw UnimplementedError();

  @override
  // TODO: implement length
  int get length => throw UnimplementedError();

  @override
  IMap<RK, RV> map<RK, RV>(MapEntry<RK, RV> Function(K key, V value) mapper,
      {bool Function(RK key, RV value)? ifRemove, ConfigMap? config}) {
    // TODO: implement map
    throw UnimplementedError();
  }

  @override
  Iterable<T> mapTo<T>(T Function(K key, V value) mapper) {
    // TODO: implement mapTo
    throw UnimplementedError();
  }

  @override
  IMap<K, V> putIfAbsent(K key, V Function() ifAbsent,
      {Output<V>? previousValue}) {
    // TODO: implement putIfAbsent
    throw UnimplementedError();
  }

  @override
  IMap<K, V> remove(K key) {
    // TODO: implement remove
    throw UnimplementedError();
  }

  @override
  IMap<K, V> removeWhere(bool Function(K key, V value) predicate) {
    // TODO: implement removeWhere
    throw UnimplementedError();
  }

  @override
  bool same(IMap<K, V> other) {
    // TODO: implement same
    throw UnimplementedError();
  }

  @override
  IList<MapEntry<K, V>> toEntryIList(
      {int Function(MapEntry<K, V>? a, MapEntry<K, V>? b)? compare,
      ConfigList? config}) {
    // TODO: implement toEntryIList
    throw UnimplementedError();
  }

  @override
  ISet<MapEntry<K, V>> toEntryISet({ConfigSet? config}) {
    // TODO: implement toEntryISet
    throw UnimplementedError();
  }

  @override
  List<MapEntry<K, V>> toEntryList(
      {int Function(MapEntry<K, V> a, MapEntry<K, V> b)? compare}) {
    // TODO: implement toEntryList
    throw UnimplementedError();
  }

  @override
  Set<MapEntry<K, V>> toEntrySet(
      {int Function(MapEntry<K, V> a, MapEntry<K, V> b)? compare}) {
    // TODO: implement toEntrySet
    throw UnimplementedError();
  }

  @override
  Object toJson(
      Object? Function(K p1) toJsonK, Object? Function(V p1) toJsonV) {
    // TODO: implement toJson
    throw UnimplementedError();
  }

  @override
  IList<K> toKeyIList({int Function(K? a, K? b)? compare, ConfigList? config}) {
    // TODO: implement toKeyIList
    throw UnimplementedError();
  }

  @override
  ISet<K> toKeyISet({ConfigSet? config}) {
    // TODO: implement toKeyISet
    throw UnimplementedError();
  }

  @override
  List<K> toKeyList({int Function(K a, K b)? compare}) {
    // TODO: implement toKeyList
    throw UnimplementedError();
  }

  @override
  Set<K> toKeySet({int Function(K a, K b)? compare}) {
    // TODO: implement toKeySet
    throw UnimplementedError();
  }

  @override
  IList<V> toValueIList(
      {bool sort = false,
      int Function(V a, V b)? compare,
      ConfigList? config}) {
    // TODO: implement toValueIList
    throw UnimplementedError();
  }

  @override
  ISet<V> toValueISet({ConfigSet? config}) {
    // TODO: implement toValueISet
    throw UnimplementedError();
  }

  @override
  List<V> toValueList({bool sort = false, int Function(V a, V b)? compare}) {
    // TODO: implement toValueList
    throw UnimplementedError();
  }

  @override
  Set<V> toValueSet({int Function(V a, V b)? compare}) {
    // TODO: implement toValueSet
    throw UnimplementedError();
  }

  @override
  // TODO: implement unlock
  Map<K, V> get unlock => throw UnimplementedError();

  @override
  // TODO: implement unlockLazy
  Map<K, V> get unlockLazy => throw UnimplementedError();

  @override
  // TODO: implement unlockSorted
  Map<K, V> get unlockSorted => throw UnimplementedError();

  @override
  // TODO: implement unlockView
  Map<K, V> get unlockView => throw UnimplementedError();

  @override
  IMap<K, V> update(K key, V Function(V value) update,
      {bool Function(K key, V value)? ifRemove,
      V Function()? ifAbsent,
      Output<V>? previousValue}) {
    // TODO: implement update
    throw UnimplementedError();
  }

  @override
  IMap<K, V> updateAll(V Function(K key, V value) update,
      {bool Function(K key, V value)? ifRemove}) {
    // TODO: implement updateAll
    throw UnimplementedError();
  }

  @override
  // TODO: implement values
  Iterable<V> get values => throw UnimplementedError();

  @override
  IMap<K, V> where(bool Function(K key, V value) test) {
    // TODO: implement where
    throw UnimplementedError();
  }

  @override
  IMap<K, V> withConfig(ConfigMap config) {
    // TODO: implement withConfig
    throw UnimplementedError();
  }

  @override
  IMap<K, V> withConfigFrom(IMap<K, V> other) {
    // TODO: implement withConfigFrom
    throw UnimplementedError();
  }

  @override
  // TODO: implement withDeepEquals
  IMap<K, V> get withDeepEquals => throw UnimplementedError();

  @override
  // TODO: implement withIdentityEquals
  IMap<K, V> get withIdentityEquals => throw UnimplementedError();
}
