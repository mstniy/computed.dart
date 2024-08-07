import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'expandos.dart';

class ConstComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  IMap<K, V> m;
  ConstComputedMap(this.m);

  @override
  Computed<V?> operator [](K key) => $(() => m[key]);
  @override
  Computed<bool> containsKey(K key) => $(() => m.containsKey(key));
  @override
  Computed<bool> containsValue(V value) => $(() => m.containsValue(value));
  @override
  Computed<ChangeEvent<K, V>> get changes => (changesExpando[this] ??=
      $(() => throw NoValueException())) as Computed<ChangeEvent<K, V>>;
  @override
  Computed<IMap<K, V>> get snapshot =>
      (snapshotExpando[this] ??= $(() => m)) as Computed<IMap<K, V>>;
  @override
  Computed<bool> get isEmpty => isEmptyExpando[this] ??= $(() => m.isEmpty);
  @override
  Computed<bool> get isNotEmpty =>
      isNotEmptyExpando[this] ??= $(() => m.isNotEmpty);
  @override
  Computed<int> get length => lengthExpando[this] ??= $(() => m.length);
}
