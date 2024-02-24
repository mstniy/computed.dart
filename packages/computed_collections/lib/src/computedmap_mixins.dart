import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

import '../icomputedmap.dart';
import 'add_computedmap.dart';

class ComputedMapMixin<K, V> {
  IComputedMap<K, V> add(K key, V value) => AddComputedMap(
      this as IComputedMap<K, V>,
      key,
      value); // Note that the computed variant is trivial
}

class ChildComputedMap<K, V> {
  final IComputedMap<K, V> parent;
  ChildComputedMap(this.parent);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void fix(IMap<K, V> value) => parent.fix(value);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void fixThrow(Object e) => parent.fixThrow(e);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IMap<K, V> Function() mock) => parent.mock(mock);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void unmock() => parent.unmock();
}
