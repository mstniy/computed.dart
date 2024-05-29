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
import 'utils/value_or_exception.dart';

Set<K>? _getAffectedKeys<K, V>(ChangeEvent<K, V> change) => switch (change) {
      ChangeEventReplace<K, V>() => null,
      KeyChanges<K, V>(changes: final changes) => changes.keys.toSet(),
    };

class ChangeStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final Computed<ChangeEvent<K, V>> _changeStream;
  // Note that this is the internal snapshot stream, used by _c
  // The user-visible one is a wrapper around _c to ensure proper bookeeping
  late final Computed<IMap<K, V>> _snapshotStream;
  // TODO: This is ridiculous
  late final Computed<(ChangeEvent<K, V>, IMap<K, V>)> _changeAndSnapshotStream;
  late final Computed<IMap<K, V>> _c;
  // The "keep-alive" subscription used by key streams, as we explicitly break the dependency DAG of Computed.
  ComputedSubscription<IMap<K, V>>? _cSub;
  late final PubSub<K, Option<V>> _keyPubSub;
  var _isInitialValue = true;
  ChangeStreamComputedMap(this._changeStream,
      {IMap<K, V> Function()? initialValueComputer,
      Computed<IMap<K, V>>? snapshotStream}) {
    _keyPubSub = PubSub<K, Option<V>>((k) {
      ////////////////////// make pubsub run this in a computation
      final m = _c.use; // Throws if there is an exception
      if (m.containsKey(k)) return Option.some(m[k]); // There is a value
      return Option.none(); // There is no value
    }, () {
      assert(_cSub == null);
      // Kickstart the keepalive subscription
      // Escape the Computed zone
      Zone.current.parent!.run(() {
        _cSub = _c.listen((e) {}, null);
      });
    }, () {
      _cSub!.cancel();
      _cSub = null;
    });
    changes = $(() => _changeStream.use);
    _snapshotStream =
        snapshotStream ?? snapshotComputation(changes, initialValueComputer);
    _changeAndSnapshotStream = $(() => (changes.use, _snapshotStream.use));
    _c = Computed.async(() {
      (ChangeEvent<K, V>, IMap<K, V>) changeAndSnapshot;
      try {
        changeAndSnapshot = _changeAndSnapshotStream.use;
      } on NoValueException {
        rethrow;
      } catch (e) {
        _notifyAllKeyStreams(e);
        throw e;
      }
      final keysToNotify = _isInitialValue
          ? null
          : _getAffectedKeys(
              changeAndSnapshot.$1); // If null -> notify all keys
      _isInitialValue = false;
      if (keysToNotify == null) {
        _notifyAllKeyStreams(null);
      } else {
        _notifyKeyStreams(keysToNotify);
      }

      return changeAndSnapshot.$2;
    }, onCancel: () => _isInitialValue = true);

    // We do not directly expose _c because it also does bookkeeping, and
    // that would get messes up if it gets mocked.
    snapshot = $(() => _c.use);
    isEmpty = $(() => _c.use.isEmpty);
    isNotEmpty = $(() => _c.use.isNotEmpty);
    length = $(() => _c.use.length);
  }

  @visibleForTesting
  void fix(IMap<K, V> value) => mock(ConstComputedMap(value));

  @visibleForTesting
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    _changeAndSnapshotStream
        // ignore: invalid_use_of_visible_for_testing_member
        .fixThrow(
            e); // Note that this will trigger [_c] to notify the key streams, if there are any
  }

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IComputedMap<K, V> mock) {
    _isInitialValue = true; // Force [_c] to notify all the key streams
    _changeAndSnapshotStream
        // ignore: invalid_use_of_visible_for_testing_member
        .mock(() => (
              mock.changes.use,
              mock.snapshot.use
            )); ////////////////////// what if [mock] has no changes?
  }

  @visibleForTesting
  void unmock() {
    _isInitialValue = true;
    // We always use replacement change streams to force [_c] to notify all the key streams
    final replacementChangeStream =
        getReplacementChangeStream(mock.snapshot, mock.changes);
    _changeAndSnapshotStream
        // ignore: invalid_use_of_visible_for_testing_member
        .mock(() => (replacementChangeStream(), mock.snapshot.use));
  }

  void _notifyAllKeyStreams(Object? exc) {
    if (exc == null) {
      _keyPubSub.recomputeAllKeys();
    } else {
      _keyPubSub.pubError(exc);
    }
  }

  void _notifyKeyStreams(Set<K> keys) {
    _keyPubSub.recomputeKeys(keys);
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
  Computed<bool> containsValue(V value) =>
      _containsValueCache.wrap(value, () => _c.use.containsValue(value));

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
