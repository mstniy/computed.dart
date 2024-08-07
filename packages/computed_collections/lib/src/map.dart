import 'package:computed/computed.dart';
import 'package:computed_collections/src/expandos.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../change_event.dart';
import '../icomputedmap.dart';
import 'computedmap_mixins.dart';
import 'utils/snapshot_computation.dart';

class MapComputedMap<K, V, KParent, VParent>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<KParent, VParent> _parent;
  final MapEntry<K, V> Function(KParent key, VParent value) _convert;

  final _mappedKeys = <KParent, K>{};
  final _mappedKeysReverse = <K, Map<KParent, V>>{};

  late final CSTracker<K, V> _tracker;

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

    return ressLocked;
  }

  MapComputedMap(this._parent, this._convert) {
    changes = Computed.async(() {
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
            return KeyChanges(keyChanges.lock);
          } else {
            throw NoValueException();
          }
      }
    }, onCancel: _onCancel);

    snapshot =
        snapshotComputation(changes, () => _setUpstream(_parent.snapshot.use));

    _tracker = CSTracker<K, V>(changes, snapshot);
  }

  void _onCancel() {
    _mappedKeys.clear();
    _mappedKeysReverse.clear();
  }

  @override
  Computed<bool> containsKey(K key) => _tracker.containsKey(key);

  @override
  Computed<V?> operator [](K key) => _tracker[key];

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  late final Computed<IMap<K, V>> snapshot;

  @override
  late final Computed<ChangeEvent<K, V>> changes;

  @override
  Computed<bool> get isEmpty => _parent.isEmpty;
  @override
  Computed<bool> get isNotEmpty => _parent.isNotEmpty;

  @override
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);
}
