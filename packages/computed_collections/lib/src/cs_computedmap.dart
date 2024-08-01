import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/pubsub.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class ChangeStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  late final PubSub<K, V> _keyPubSub;
  ChangeStreamComputedMap(this.changes,
      {IMap<K, V> Function()? initialValueComputer,
      Computed<IMap<K, V>>? snapshotStream}) {
    snapshot =
        snapshotStream ?? snapshotComputation(changes, initialValueComputer);
    _keyPubSub = PubSub(changes, snapshot);
  }

  Computed<V?> operator [](K key) {
    final keySub = _keyPubSub.subKey(key);
    return $(() {
      final keyOption = keySub.use;
      if (keyOption.is_) return keyOption.value;
      return null;
    });
  }

  @override
  Computed<bool> containsKey(K key) {
    final keySub = _keyPubSub.subKey(key);
    return $(() {
      final keyOption = keySub.use;
      return keyOption.is_;
    });
  }

  @override
  Computed<bool> containsValue(V value) => _keyPubSub.containsValue(value);

  @override
  Computed<ChangeEvent<K, V>> changes;

  @override
  Computed<bool> get isEmpty => $(() => snapshot.use.isEmpty);

  @override
  Computed<bool> get isNotEmpty => $(() => snapshot.use.isNotEmpty);

  @override
  Computed<int> get length => $(() => snapshot.use.length);

  @override
  late final Computed<IMap<K, V>> snapshot;
}
