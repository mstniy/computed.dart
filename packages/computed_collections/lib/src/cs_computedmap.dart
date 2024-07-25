import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/pubsub.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:meta/meta.dart';

import 'computedmap_mixins.dart';
import 'const_computedmap.dart';

class ChangeStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final Computed<ChangeEvent<K, V>> _changeStream;
  late final Computed<ChangeEvent<K, V>> _changeStreamWrapped;
  late final Computed<IMap<K, V>> _snapshotStream;
  late final PubSub<K, V> _keyPubSub;
  // Note that the instance may mock the given snapshot stream
  ChangeStreamComputedMap(this._changeStream,
      {IMap<K, V> Function()? initialValueComputer,
      Computed<IMap<K, V>>? snapshotStream}) {
    _changeStreamWrapped = $(() => _changeStream.use);
    // Passing _changeStreamWrapped to KeyPub allows it to be consistent with mocks
    _keyPubSub = PubSub(_changeStreamWrapped,
        initialValueComputer: initialValueComputer,
        snapshotStream: snapshotStream);
    _snapshotStream = _keyPubSub.snapshot;
  }

  @visibleForTesting
  void fix(IMap<K, V> value) => mock(ConstComputedMap(value));

  @visibleForTesting
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshotStream.fixThrow(e);
    // ignore: invalid_use_of_visible_for_testing_member
    _changeStreamWrapped.fixThrow(e);
  }

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IComputedMap<K, V> mock) {
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshotStream.mock(() => mock.snapshot.use);
    // This logic is copied over from MockManager
    if (changesHasListeners(_changeStreamWrapped)) {
      // We have to mock to a "replacement stream" that emits
      // a replacement event to keep the existing listeners in sync
      _changeStreamWrapped
          // ignore: invalid_use_of_visible_for_testing_member
          .mock(getReplacementChangeStream(mock.snapshot, mock.changes));
    } else {
      // If there are no existing listeners, we can be naive
      // ignore: invalid_use_of_visible_for_testing_member
      _changeStreamWrapped.mock(() => mock.changes.use);
    }
  }

  @visibleForTesting
  void unmock() {
    // See the corresponding part in [mock]
    if (changesHasListeners(_changeStreamWrapped)) {
      _changeStreamWrapped
          // ignore: invalid_use_of_visible_for_testing_member
          .mock(getReplacementChangeStream(_snapshotStream, _changeStream));
    } else {
      // ignore: invalid_use_of_visible_for_testing_member
      _changeStreamWrapped.unmock();
    }
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshotStream.unmock();
  }

  Computed<V?> operator [](K key) {
    final keySub = _keyPubSub.sub(key);
    return $(() {
      final keyOption = keySub.use;
      if (keyOption.is_) return keyOption.value;
      return null;
    });
  }

  @override
  Computed<bool> containsKey(K key) {
    final keySub = _keyPubSub.sub(key);
    return $(() {
      final keyOption = keySub.use;
      return keyOption.is_;
    });
  }

  final _containsValueCache = ComputationCache<V, bool>();

  @override
  Computed<bool> containsValue(V value) => _containsValueCache.wrap(
      value, () => _snapshotStream.use.containsValue(value));

  @override
  Computed<ChangeEvent<K, V>> get changes => $(() => _changeStreamWrapped.use);

  @override
  Computed<bool> get isEmpty => $(() => _snapshotStream.use.isEmpty);

  @override
  Computed<bool> get isNotEmpty => $(() => _snapshotStream.use.isNotEmpty);

  @override
  Computed<int> get length => $(() => _snapshotStream.use.length);

  @override
  Computed<IMap<K, V>> get snapshot => $(() => _snapshotStream.use);
}
