import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class ConstComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final Computed<IMap<K, V>> _snapshot;
  final Computed<ChangeEvent<K, V>> _changes =
      $(() => throw NoValueException());

  ConstComputedMap(IMap<K, V> m) : _snapshot = $(() => m);

  @override
  Computed<V?> operator [](K key) => $(() => _snapshot.use[key]);

  @override
  Computed<bool> containsKey(K key) => $(() => _snapshot.use.containsKey(key));

  @override
  Computed<bool> containsValue(V value) =>
      $(() => _snapshot.use.containsValue(value));

  @override
  void fix(IMap<K, V> m) {
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshot.fix(m);
    if (changesHasListeners(_changes)) {
      // ignore: invalid_use_of_visible_for_testing_member
      _changes.mock(getReplacementChangeStream(
          _snapshot, $(() => throw NoValueException())));
    } else {
      // We might be already mocked to some other computed collection
      // ignore: invalid_use_of_visible_for_testing_member
      _changes.mock(() => throw NoValueException());
    }
  }

  @override
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshot.fixThrow(e);
    // ignore: invalid_use_of_visible_for_testing_member
    _changes.fixThrow(e);
  }

  @override
  void mock(IComputedMap<K, V> mock) {
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshot.mock(() => mock.snapshot.use);
    if (changesHasListeners(_changes)) {
      // ignore: invalid_use_of_visible_for_testing_member
      _changes.mock(getReplacementChangeStream(mock.snapshot, mock.changes));
    } else {
      // ignore: invalid_use_of_visible_for_testing_member
      _changes.mock(() => mock.changes.use);
    }
  }

  @override
  void unmock() {
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshot.unmock();
    if (changesHasListeners(_changes)) {
      // ignore: invalid_use_of_visible_for_testing_member
      _changes.mock(getReplacementChangeStream(
          _snapshot, $(() => throw NoValueException())));
    } else {
      // ignore: invalid_use_of_visible_for_testing_member
      _changes.unmock();
    }
  }

  @override
  Computed<ChangeEvent<K, V>> get changes => $(() => _changes.use);
  @override
  Computed<IMap<K, V>> get snapshot => $(() => _snapshot.use);
  @override
  Computed<bool> get isEmpty => $(() => _snapshot.use.isEmpty);
  @override
  Computed<bool> get isNotEmpty => $(() => _snapshot.use.isNotEmpty);
  @override
  Computed<int> get length => $(() => _snapshot.use.length);
}
