import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

/// An [IComputedMap] represented by a change and a snapshot stream.
class SnapshotChangeStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final Computed<bool> isEmpty;
  final Computed<bool> isNotEmpty;
  final Computed<int> length;
  final Computed<ChangeEvent<K, V>> changes;
  final Computed<IMap<K, V>> snapshot;

  SnapshotChangeStreamComputedMap(
      Stream<ChangeEvent<K, V>> _changes, Stream<IMap<K, V>> _snapshot)
      : isEmpty = $(() => _snapshot.use.isEmpty),
        isNotEmpty = $(() => _snapshot.use.isNotEmpty),
        length = $(() => _snapshot.use.length),
        changes = $(() {
          ChangeEvent<K, V>? change;
          _changes.react((c) {
            change = c;
          });
          if (change == null) throw NoValueException();
          return change!;
        }),
        snapshot = $(() => _snapshot.use);

  @override
  // TODO: ChangeStreamComputedMap does it better.
  //  This approach re-computed the existance of all keys any time the snapshot changes,
  //  which is inefficient.
  Computed<bool> containsKey(K key) => $(() => snapshot.use.containsKey(key));

  @override
  Computed<V?> operator [](K key) => $(() => snapshot.use[key]);

  @override
  Computed<bool> containsValue(V value) =>
      $(() => snapshot.use.containsValue(value));

  static const _mockErrorMessage =
      "Please mock the result of `.groupBy` instead.";

  @override
  void fix(IMap<K, V> value) => throw UnsupportedError(_mockErrorMessage);

  @override
  void fixThrow(Object e) => throw UnsupportedError(_mockErrorMessage);

  @override
  void mock(IComputedMap<K, V> mock) =>
      throw UnsupportedError(_mockErrorMessage);

  @override
  void unmock() => throw UnsupportedError(_mockErrorMessage);
}
