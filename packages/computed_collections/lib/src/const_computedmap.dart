import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class ConstComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final IMap<K, V> m;
  final Computed<IMap<K, V>> snapshot;
  final Computed<bool> isEmpty;
  final Computed<bool> isNotEmpty;
  final Computed<int> length;

  ConstComputedMap(this.m)
      : snapshot = $(() => m),
        isEmpty = $(() => m.isEmpty),
        isNotEmpty = $(() => m.isNotEmpty),
        length = $(() => m.length);

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
    isEmpty.fix(m.isEmpty);
    // ignore: invalid_use_of_visible_for_testing_member
    isNotEmpty.fix(m.isNotEmpty);
    // ignore: invalid_use_of_visible_for_testing_member
    length.fix(m.length);
    // ignore: invalid_use_of_visible_for_testing_member
    changes.fix(ChangeEventReplace(m));
  }

  @override
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    snapshot.fixThrow(e);
    // ignore: invalid_use_of_visible_for_testing_member
    isEmpty.fixThrow(e);
    // ignore: invalid_use_of_visible_for_testing_member
    isNotEmpty.fixThrow(e);
    // ignore: invalid_use_of_visible_for_testing_member
    length.fixThrow(e);
    // ignore: invalid_use_of_visible_for_testing_member
    changes.fixThrow(e);
  }

  @override
  void mock(IComputedMap<K, V> mock) {
    // ignore: invalid_use_of_visible_for_testing_member
    snapshot.mock(() => mock.snapshot.use);
    // ignore: invalid_use_of_visible_for_testing_member
    isEmpty.mock(() => mock.isEmpty.use);
    // ignore: invalid_use_of_visible_for_testing_member
    isNotEmpty.mock(() => mock.isNotEmpty.use);
    // ignore: invalid_use_of_visible_for_testing_member
    length.mock(() => mock.length.use);
    // ignore: invalid_use_of_visible_for_testing_member
    changes.mock(() => ChangeEventReplace(mock.snapshot.use));
  }

  @override
  void unmock() {
    // ignore: invalid_use_of_visible_for_testing_member
    snapshot.unmock();
    // ignore: invalid_use_of_visible_for_testing_member
    isEmpty.unmock();
    // ignore: invalid_use_of_visible_for_testing_member
    isNotEmpty.unmock();
    // ignore: invalid_use_of_visible_for_testing_member
    length.unmock();
    // ignore: invalid_use_of_visible_for_testing_member
    changes.mock(() => ChangeEventReplace(m));
  }
}
