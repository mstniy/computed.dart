import 'package:computed/computed.dart';
import 'package:computed_collections/src/expandos.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../change_event.dart';
import '../computedmap.dart';
import 'computedmap_mixins.dart';
import 'utils/snapshot_computation.dart';

class MapComputedMap<K, V, KParent, VParent>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  final ComputedMap<KParent, VParent> _parent;
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
      if (!ress.containsKey(res.key)) {
        ress[res.key] = res.value;
      }
      final group = _mappedKeysReverse[res.key] ??= {};
      group[e.key] = res.value;
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

          void removeKeyFromGroup(KParent kparent, K k) {
            final oldGroup = _mappedKeysReverse[k]!;
            final wasActive = kparent == oldGroup.keys.first;
            assert(oldGroup.containsKey(kparent));
            oldGroup.remove(kparent);
            if (oldGroup.isEmpty) {
              _mappedKeysReverse.remove(k);
              keyChanges[k] = ChangeRecordDelete();
            } else if (wasActive) {
              keyChanges[k] = ChangeRecordValue(oldGroup.values.first);
            }
          }

          for (var e in changes.entries) {
            switch (e.value) {
              case ChangeRecordValue<VParent>(value: final value):
                final converted = _convert(e.key, value);
                if (_mappedKeys.containsKey(e.key) &&
                    _mappedKeys[e.key] != converted.key) {
                  // Mapped key changed - remove the parent key from the old mapped key
                  final oldMappedKey = _mappedKeys[e.key] as K;
                  removeKeyFromGroup(e.key, oldMappedKey);
                }
                _mappedKeys[e.key] = converted.key;
                final newGroup = _mappedKeysReverse[converted.key] ??= {};
                newGroup[e.key] = converted.value;
                if (newGroup.keys.first == e.key) {
                  keyChanges[converted.key] =
                      ChangeRecordValue(converted.value);
                }
              case ChangeRecordDelete<VParent>():
                if (!_mappedKeys.containsKey(e.key)) {
                  // Duplicate deletion from upstream
                  continue;
                }
                final oldMappedKey = _mappedKeys.remove(e.key) as K;
                removeKeyFromGroup(e.key, oldMappedKey);
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
