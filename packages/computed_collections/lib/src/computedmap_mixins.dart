import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/src/const_computedmap.dart';
import 'package:computed_collections/src/group_by.dart';
import 'package:computed_collections/src/group_by_computed.dart';
import 'package:computed_collections/src/map_values.dart';
import 'package:computed_collections/src/map_values_computed.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../change_event.dart';
import '../icomputedmap.dart';
import 'add_computedmap.dart';

mixin OperatorsMixin<K, V> {
  IComputedMap<K, V> add(K key, V value) =>
      AddComputedMap(this as IComputedMap<K, V>, key, value);

  IComputedMap<K, V> addAll(IMap<K, V> other) {
    // TODO: implement addAll
    throw UnimplementedError();
  }

  IComputedMap<K, V> addAllComputed(IComputedMap<K, V> other) {
    // TODO: implement addAllComputed
    throw UnimplementedError();
  }

  IComputedMap<RK, RV> cast<RK, RV>() {
    // TODO: implement cast
    throw UnimplementedError();
  }

  IComputedMap<K2, V2> map<K2, V2>(
      MapEntry<K2, V2> Function(K key, V value) convert) {
    // TODO: implement map
    throw UnimplementedError();
  }

  IComputedMap<K2, V2> mapComputed<K2, V2>(
      Computed<MapEntry<K2, V2>> Function(K key, V value) convert) {
    // TODO: implement mapComputed
    throw UnimplementedError();
  }

  IComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V value) convert) =>
      MapValuesComputedMap(this as IComputedMap<K, V>, convert);

  IComputedMap<K, V2> mapValuesComputed<V2>(
          Computed<V2> Function(K key, V value) convert) =>
      MapValuesComputedComputedMap(this as IComputedMap<K, V>, convert);

  IComputedMap<K, V> putIfAbsent(K key, V Function() ifAbsent) {
    // TODO: implement putIfAbsent
    throw UnimplementedError();
  }

  IComputedMap<K, V> remove(K key) {
    // TODO: implement remove
    throw UnimplementedError();
  }

  IComputedMap<K, V> removeWhere(bool Function(K key, V value) test) {
    // TODO: implement removeWhere
    throw UnimplementedError();
  }

  IComputedMap<K, V> removeWhereComputed(
      Computed<bool> Function(K key, V value) test) {
    // TODO: implement removeWhereComputed
    throw UnimplementedError();
  }

  IComputedMap<K, V> update(K key, V Function(V value) update,
      {V Function()? ifAbsent}) {
    // TODO: implement update
    throw UnimplementedError();
  }

  IComputedMap<K, V> updateAll(V Function(K key, V value) update) {
    // TODO: implement updateAll
    throw UnimplementedError();
  }

  IComputedMap<K, V> updateAllComputed(
      Computed<V> Function(K key, V value) update) {
    // TODO: implement updateAllComputed
    throw UnimplementedError();
  }

  IComputedMap<K2, IComputedMap<K, V>> groupBy<K2>(
          K2 Function(K key, V value) key) =>
      GroupByComputedMap(this as IComputedMap<K, V>, key);

  IComputedMap<K2, IComputedMap<K, V>> groupByComputed<K2>(
          Computed<K2> Function(K key, V value) key) =>
      GroupByComputedComputedMap(this as IComputedMap<K, V>, key);
}

class MockManager<K, V> {
  final Computed<ChangeEvent<K, V>> _changes;
  late final Computed<ChangeEvent<K, V>> _changes_wrapped;
  final Computed<IMap<K, V>> _snapshot;
  final Computed<int> _length;
  final Computed<bool> _isEmpty;
  final Computed<bool> _isNotEmpty;
  final ComputationCache<K, V?> _keyComputations;
  final ComputationCache<K, bool> _containsKeyComputations;
  final ComputationCache<V, bool> _containsValueComputations;

  MockManager(
      this._changes,
      this._snapshot,
      this._length,
      this._isEmpty,
      this._isNotEmpty,
      this._keyComputations,
      this._containsKeyComputations,
      this._containsValueComputations) {
    _changes_wrapped = $(() => _changes.use);
  }

  void fix(IMap<K, V> value) => mock(ConstComputedMap(value));

  void fixThrow(Object e) {
    for (var c in [_changes, _snapshot, _isEmpty, _isNotEmpty, _length]) {
      // ignore: invalid_use_of_visible_for_testing_member
      c.fixThrow(e);
    }
    for (var cc in [
      _keyComputations,
      _containsKeyComputations,
      _containsValueComputations
    ]) {
      // ignore: invalid_use_of_visible_for_testing_member
      cc.mock((key) => throw e);
    }
  }

  void mock(IComputedMap<K, V> mock) {
    if (changesHasListeners(_changes_wrapped)) {
      // We have to mock to a "replacement stream" that emits
      // a replacement event to keep the existing listeners in sync
      _changes_wrapped
          // ignore: invalid_use_of_visible_for_testing_member
          .mock(getReplacementChangeStream(mock.snapshot, mock.changes));
    } else {
      // If there are no existing listeners, we can be naive
      // ignore: invalid_use_of_visible_for_testing_member
      _changes_wrapped.mock(() => mock.changes.use);
    }
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshot.mock(() => mock.snapshot.use);
    // ignore: invalid_use_of_visible_for_testing_member
    _keyComputations.mock((key) => mock[key].use);
    // Note that this pattern (of calling functions that return computations and `use`ing their results)
    // inside another computation) assumes that they will always return the exact same computation
    // for long as there is a listener (note that `ComputationCache` satisfies this).
    // ignore: invalid_use_of_visible_for_testing_member
    _containsKeyComputations.mock((key) => mock.containsKey(key).use);
    // ignore: invalid_use_of_visible_for_testing_member
    _containsValueComputations.mock((v) => mock.containsValue(v).use);
    // ignore: invalid_use_of_visible_for_testing_member
    _isEmpty.mock(() => mock.isEmpty.use);
    // ignore: invalid_use_of_visible_for_testing_member
    _isNotEmpty.mock(() => mock.isNotEmpty.use);
    // ignore: invalid_use_of_visible_for_testing_member
    _length.mock(() => mock.length.use);
  }

  void unmock() {
    for (var c in [_snapshot, _isEmpty, _isNotEmpty, _length]) {
      // ignore: invalid_use_of_visible_for_testing_member
      c.unmock();
    }
    for (var cc in [
      _keyComputations,
      _containsKeyComputations,
      _containsValueComputations
    ]) {
      // ignore: invalid_use_of_visible_for_testing_member
      cc.unmock();
    }

    // See the corresponding part in [mock]
    if (changesHasListeners(_changes_wrapped)) {
      // ignore: invalid_use_of_visible_for_testing_member
      _changes_wrapped.mock(getReplacementChangeStream(_snapshot, _changes));
    } else {
      // ignore: invalid_use_of_visible_for_testing_member
      _changes_wrapped.unmock();
    }
  }

  // Wrap all these to make sure they return different instances each time
  // This results in more intuitive behaviour when they are mocked
  Computed<ChangeEvent<K, V>> get changes => $(() => _changes_wrapped.use);
  Computed<IMap<K, V>> get snapshot => $(() => _snapshot.use);
  Computed<int> get length => $(() => _length.use);
  Computed<bool> get isEmpty => $(() => _isEmpty.use);
  Computed<bool> get isNotEmpty => $(() => _isNotEmpty.use);
}

ChangeEvent<K, V> Function() getReplacementChangeStream<K, V>(
    Computed<IMap<K, V>> snapshot, Computed<ChangeEvent<K, V>> changeStream) {
  // Note that we do NOT need to aggregate the changes we receive until we receive a snapshot
  // Because there is no computed collection that gains a snapshot after gaining a change stream.
  var firstEmit = true;

  final cs = Computed(() {
    if (firstEmit) {
      // First emit a replacement to the snapshot of the new collection
      final s = snapshot.use;
      try {
        changeStream.use; // Subscribe to it
      } on NoValueException {
        // pass
      }
      firstEmit = false;
      return ChangeEventReplace(s);
    }
    return changeStream.use; // Then delegate to the change stream
  }, assertIdempotent: false, onCancel: () => firstEmit = false);
  return () => cs.use;
}

bool changesHasListeners<K, V>(Computed<ChangeEvent<K, V>> changes) {
  var hasListeners = false;
  // ignore: invalid_use_of_visible_for_testing_member
  changes.mock(() {
    hasListeners = true;
    // This is fine because we throw NoValueException
    throw NoValueException();
  });
  return hasListeners;
}
