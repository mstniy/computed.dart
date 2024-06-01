import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/pubsub.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:meta/meta.dart';

import 'computedmap_mixins.dart';
import 'const_computedmap.dart';
import 'utils/option.dart';

class ChangeStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final Computed<ChangeEvent<K, V>> _changeStream;
  // Note that this is the internal snapshot stream, used by _c
  // The user-visible one is a wrapper around _c to ensure proper bookeeping
  late final Computed<IMap<K, V>> _snapshotStream;
  late final Computed<void> _c;
  // The "keep-alive" subscription used by key streams, as we explicitly break the dependency DAG of Computed.
  ComputedSubscription<void>? _cSub;
  late final PubSub<K, V> _keyPubSub;
  var _isInitialValue = true;
  ChangeStreamComputedMap(this._changeStream,
      {IMap<K, V> Function()? initialValueComputer,
      Computed<IMap<K, V>>? snapshotStream}) {
    _keyPubSub = PubSub<K, V>(() {
      assert(_cSub == null);
      // Kickstart the keepalive subscription
      // Escape the Computed zone
      Zone.current.parent!.run(() {
        _cSub = _c.listen(null, null);
      });
    }, () {
      _cSub!.cancel();
      _cSub = null;
    });
    changes = $(() => _changeStream.use);
    _snapshotStream =
        snapshotStream ?? snapshotComputation(changes, initialValueComputer);
    // TODO: Make this into an effect instead of an async computation and an empty listener
    //  after we introduce effect onCancel
    _c = Computed.async(() {
      IMap<K, V> snapshot;
      try {
        snapshot = _snapshotStream.use;
      } on NoValueException {
        rethrow;
      } catch (e) {
        _keyPubSub.pubError(e);
        return;
      }
      if (_isInitialValue) {
        _isInitialValue = false;
      } else {
        // We really should not get any exception here
        // As we are not in the initial computation and we got a (new) snapshot,
        // so there must be a change.
        // If this [.use] nevertheless throws, we'll end up reporting an
        // uncaught error to the current zone, which is desired.
        final change = _changeStream.use;
        if (change is KeyChanges<K, V>) {
          _keyPubSub.pubMany(change.changes.map((key, value) => MapEntry(
              key,
              switch (value) {
                ChangeRecordValue<V>(value: final value) => Option.some(value),
                ChangeRecordDelete<V>() => Option.none(),
              })));
          return; // Do not call pubAll
        }
      }

      _keyPubSub.pubAll(snapshot);
    }, onCancel: () => _isInitialValue = true);

    // We do not directly expose _c because it also does bookkeeping, and
    // that would get messes up if it gets mocked.
    snapshot = $(() => _snapshotStream.use);
    isEmpty = $(() => _snapshotStream.use.isEmpty);
    isNotEmpty = $(() => _snapshotStream.use.isNotEmpty);
    length = $(() => _snapshotStream.use.length);
  }

  @visibleForTesting
  void fix(IMap<K, V> value) => mock(ConstComputedMap(value));

  @visibleForTesting
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshotStream.fixThrow(e);
    // Note that by now [_c] has stopped listening to the [_changeStream].
    // ignore: invalid_use_of_visible_for_testing_member
    _changeStream.fixThrow(e);
  }

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IComputedMap<K, V> mock) {
    _isInitialValue = true; // Force [_c] to notify all the key streams
    // ignore: invalid_use_of_visible_for_testing_member
    _snapshotStream.mock(() => mock.snapshot.use);
    // Note that by now [_c] has stopped listening to the [_changeStream].
    // ignore: invalid_use_of_visible_for_testing_member
    _changeStream.mock(() => mock.changes.use);
  }

  @visibleForTesting
  void unmock() {
    _isInitialValue = true; // Force [_c] to notify all the key streams
    // ignore: invalid_use_of_visible_for_testing_member
    _changeStream.unmock();
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
  late final Computed<ChangeEvent<K, V>>
      changes; // TODO: Make these getters returning new computations at each call

  @override
  late final Computed<bool> isEmpty;

  @override
  late final Computed<bool> isNotEmpty;

  @override
  late final Computed<int> length;

  @override
  late final Computed<IMap<K, V>> snapshot;
}
