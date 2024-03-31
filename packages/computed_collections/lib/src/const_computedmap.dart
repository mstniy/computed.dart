import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class ConstComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final Computed<IMap<K, V>> snapshot;
  late final Computed<bool> isEmpty;
  late final Computed<bool> isNotEmpty;
  late final Computed<int> length;

  ConstComputedMap(IMap<K, V> m) : snapshot = $(() => m) {
    isEmpty = $(() => snapshot.use.isEmpty);
    isNotEmpty = $(() => snapshot.use.isNotEmpty);
    length = $(() => snapshot.use.length);
  }

  @override
  Computed<V?> operator [](K key) => $(() => snapshot.use[key]);

  final changes = Computed<ChangeEvent<K, V>>(() => throw NoValueException());

  @override
  Computed<bool> containsKey(K key) => $(() => snapshot.use.containsKey(key));

  @override
  Computed<bool> containsValue(V value) =>
      $(() => snapshot.use.containsValue(value));

  @override
  void fix(IMap<K, V> m) {
    // ignore: invalid_use_of_visible_for_testing_member
    snapshot.fix(m);
    // ignore: invalid_use_of_visible_for_testing_member
    changes.fix(ChangeEventReplace(m));
  }

  @override
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    snapshot.fixThrow(e);
    // ignore: invalid_use_of_visible_for_testing_member
    changes.fixThrow(e);
  }

  @override
  void mock(IComputedMap<K, V> mock) {
    // ignore: invalid_use_of_visible_for_testing_member
    snapshot.mock(() => mock.snapshot.use);
    // ignore: invalid_use_of_visible_for_testing_member
    changes.mock(() => ChangeEventReplace(mock.snapshot.use));
  }

  @override
  void unmock() {
    // ignore: invalid_use_of_visible_for_testing_member
    snapshot.unmock();
    // ignore: invalid_use_of_visible_for_testing_member
    changes.unmock();
  }
}
