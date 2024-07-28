import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

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
  Computed<ChangeEvent<K, V>> get changes => $(() => throw NoValueException());
  @override
  Computed<IMap<K, V>> get snapshot => $(() => m);
  @override
  Computed<bool> get isEmpty => $(() => m.isEmpty);
  @override
  Computed<bool> get isNotEmpty => $(() => m.isNotEmpty);
  @override
  Computed<int> get length => $(() => m.length);
}
