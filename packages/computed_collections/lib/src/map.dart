import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/src/utils/pubsub.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../change_event.dart';
import '../icomputedmap.dart';
import 'computedmap_mixins.dart';
import 'utils/option.dart';
import 'utils/snapshot_computation.dart';

class MapComputedMap<K, V, KParent, VParent>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  late final MockManager<K, V> _mm;

  final IComputedMap<KParent, VParent> _parent;
  final MapEntry<K, V> Function(KParent key, VParent value) _convert;

  late final Computed<IMap<K, V>> _snapshot;
  final _keyComputations = ComputationCache<K, V?>();
  final _containsKeyComputations = ComputationCache<K, bool>();
  final _containsValueComputations = ComputationCache<V, bool>();

  final _mappedKeys = <KParent, K>{};
  final _mappedKeysReverse = <K, Map<KParent, V>>{};

  ComputedSubscription<void>? _pubSubListener;
  late final PubSub<K, V> _keyPubSub;

  IMap<K, V> _setUpstream(IMap<KParent, VParent> up) {
    _mappedKeys.clear();
    _mappedKeysReverse.clear();

    final ress = <K, V>{};

    for (var e in up.entries) {
      final res = _convert(e.key, e.value);
      _mappedKeys[e.key] = res.key;
      ress[res.key] = res.value;
      _mappedKeysReverse.update(res.key, (mKR) {
        mKR[e.key] = res.value;
        return mKR;
      }, ifAbsent: () => {e.key: res.value});
    }

    final ressLocked = ress.lock;

    _keyPubSub.pubAll(ressLocked);

    return ressLocked;
  }

  MapComputedMap(this._parent, this._convert) {
    final changes = Computed.async(() {
      final change = _parent.changes.use;

      switch (change) {
        case ChangeEventReplace<KParent, VParent>():
          return ChangeEventReplace(_setUpstream(change.newCollection));
        case KeyChanges<KParent, VParent>(changes: final changes):
          final keyChanges = <K, ChangeRecord<V>>{};

          for (var e in changes.entries) {
            switch (e.value) {
              case ChangeRecordValue<VParent>(value: final value):
                final converted = _convert(e.key, value);
                _mappedKeys[e.key] = converted.key;
                _mappedKeysReverse.update(converted.key, (m) {
                  m[e.key] = converted.value;
                  return m;
                }, ifAbsent: () => {e.key: converted.value});
                keyChanges[converted.key] = ChangeRecordValue(converted.value);
              case ChangeRecordDelete<VParent>():
                if (!_mappedKeys.containsKey(e.key)) {
                  // Duplicate deletion from upstream
                  continue;
                }
                final oldMappedKey = _mappedKeys.remove(e.key) as K;
                var wasActive;
                final newParentKeyList =
                    _mappedKeysReverse.update(oldMappedKey, (s) {
                  wasActive = e.key == s.keys.last;
                  return s..remove(e.key);
                });
                if (newParentKeyList.isEmpty) {
                  _mappedKeysReverse.remove(oldMappedKey);
                  keyChanges[oldMappedKey] = ChangeRecordDelete();
                } else if (wasActive) {
                  keyChanges[oldMappedKey] =
                      ChangeRecordValue(newParentKeyList.values.last);
                }
            }
          }

          if (keyChanges.isNotEmpty) {
            _keyPubSub.pubMany(keyChanges
                .map((key, value) => MapEntry(
                    key,
                    switch (value) {
                      ChangeRecordValue<V>() => Option.some(value.value),
                      ChangeRecordDelete<V>() => Option<V>.none(),
                    }))
                .toIMap());
            return KeyChanges(keyChanges.lock);
          } else {
            throw NoValueException();
          }
      }
    }, onCancel: _onCancel);
    _snapshot =
        snapshotComputation(changes, () => _setUpstream(_parent.snapshot.use));

    _keyPubSub = PubSub<K, V>(() {
      /////////// this logic is broken if _snapshot already has listeners, but not pubsub
      _pubSubListener = _snapshot.listen(null, null);
    }, () {
      _pubSubListener!.cancel();
    });

    _mm = MockManager(
        changes,
        _snapshot,
        $(() => snapshot.use.length),
        $(() => _parent.isEmpty.use),
        $(() => _parent.isNotEmpty.use),
        _keyComputations,
        _containsKeyComputations,
        _containsValueComputations);
  }

  void _onCancel() {
    _mappedKeys.clear();
    _mappedKeysReverse.clear();
  }

  @override
  Computed<bool> containsKey(K key) {
    final sub = _keyPubSub.sub(key);
    return _containsKeyComputations.wrap(key, () => sub.use.is_);
  }

  @override
  Computed<V?> operator [](K key) {
    final sub = _keyPubSub.sub(key);
    return _keyComputations.wrap(key, () {
      final opt = sub.use;
      return opt.is_ ? opt.value as V : null;
    });
  }

  @override
  // TODO: This can be made more scalable by using a pubsub on values
  Computed<bool> containsValue(V value) => _containsValueComputations.wrap(
      value, () => _snapshot.use.containsValue(value));

  @override
  void fix(IMap<K, V> value) => _mm.fix(value);

  @override
  void fixThrow(Object e) => _mm.fixThrow(e);

  @override
  void mock(IComputedMap<K, V> mock) => _mm.mock(mock);

  @override
  void unmock() => _mm.unmock();

  @override
  Computed<IMap<K, V>> get snapshot => _mm.snapshot;

  @override
  Computed<ChangeEvent<K, V>> get changes => _mm.changes;

  @override
  Computed<bool> get isEmpty => _mm.isEmpty;
  @override
  Computed<bool> get isNotEmpty => _mm.isNotEmpty;

  @override
  Computed<int> get length => _mm.length;
}
