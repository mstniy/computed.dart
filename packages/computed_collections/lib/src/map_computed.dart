import 'package:computed/computed.dart';
import 'package:computed_collections/src/expandos.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../change_event.dart';
import '../computedmap.dart';
import 'computedmap_mixins.dart';
import 'utils/merging_change_stream.dart';
import 'utils/option.dart';
import 'utils/snapshot_computation.dart';

class MapComputedComputedMap<K, V, KParent, VParent>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  final ComputedMap<KParent, VParent> _parent;
  final Computed<Entry<K, V>> Function(KParent key, VParent value) _convert;

  late final MergingChangeStream<K, V> _changes;

  late final CSTracker<K, V> _tracker;

  final _mappedKeysSubs =
      <KParent, (Option<K>, ComputedSubscription<Entry<K, V>>)>{};
  final _mappedKeysReverse = <K, Map<KParent, V>>{};

  void _onConvertEntry(KParent parentKey, V value, K key) {
    late final Option<K> maybeOldKey;
    _mappedKeysSubs.update(parentKey, (mks) {
      maybeOldKey = mks.$1;
      return (Option.some(key), mks.$2);
    });
    late final bool keyValueChanged;
    _mappedKeysReverse.update(key, (entries) {
      keyValueChanged = parentKey == entries.keys.first;
      entries[parentKey] = value;
      return entries;
    }, ifAbsent: () {
      keyValueChanged = true;
      return {parentKey: value};
    });
    if (keyValueChanged) {
      _changes.add(
          KeyChanges(<K, ChangeRecord<V>>{key: ChangeRecordValue(value)}.lock));
    }

    if (maybeOldKey.is_ && maybeOldKey.value != key) {
      final oldKey = maybeOldKey.value as K;
      late final bool oldKeyValueChanged;
      final oldKeyNewEntires = _mappedKeysReverse.update(oldKey, (entries) {
        oldKeyValueChanged = parentKey == entries.keys.first;
        entries.remove(parentKey);
        return entries;
      });
      if (oldKeyNewEntires.isEmpty) {
        _mappedKeysReverse.remove(oldKey);
        _changes.add(KeyChanges(
            <K, ChangeRecord<V>>{oldKey: ChangeRecordDelete<V>()}.lock));
      } else {
        if (oldKeyValueChanged) {
          _changes.add(KeyChanges(<K, ChangeRecord<V>>{
            oldKey: ChangeRecordValue(oldKeyNewEntires.values.first)
          }.lock));
        }
      }
    }
  }

  void _setUpstream(IMap<KParent, VParent> up) {
    for (var e in _mappedKeysSubs.values) {
      e.$2.cancel();
    }
    _mappedKeysSubs.clear();
    _mappedKeysReverse.clear();

    for (var e in up.entries) {
      final res = _convert(e.key, e.value);
      _mappedKeysSubs[e.key] = (
        Option.none(),
        res.listen(
            (ce) => _onConvertEntry(e.key, ce.value, ce.key), _changes.addError)
      );
    }
  }

  MapComputedComputedMap(this._parent, this._convert) {
    final computedChanges = Computed.async(() {
      final change = _parent.changes.use;

      switch (change) {
        case ChangeEventReplace<KParent, VParent>():
          _setUpstream(change.newCollection);
          return ChangeEventReplace(<K, V>{}.lock);
        case KeyChanges<KParent, VParent>(changes: final changes):
          final keyChanges = <K, ChangeRecord<V>>{};

          void removeKey(KParent kparent, Option<K> maybeKey) {
            if (maybeKey.is_) {
              final key = maybeKey.value as K;
              late final bool oldKeyValueChanged;
              final oldKeyNewEntries = _mappedKeysReverse.update(key, (m) {
                oldKeyValueChanged = kparent == m.keys.first;
                m.remove(kparent);
                return m;
              });
              if (oldKeyNewEntries.isEmpty) {
                keyChanges[key] = ChangeRecordDelete();
                _mappedKeysReverse.remove(key);
              } else if (oldKeyValueChanged) {
                keyChanges[key] =
                    ChangeRecordValue(oldKeyNewEntries.values.first);
              }
            }
          }

          for (var e in changes.entries) {
            switch (e.value) {
              case ChangeRecordValue<VParent>(value: final value):
                final converted = _convert(e.key, value);
                final sub = converted.listen(
                    (event) => _onConvertEntry(e.key, event.value, event.key),
                    _changes.addError);
                late final Option<K> oldKeyMaybe;
                _mappedKeysSubs.update(e.key, (ks) {
                  oldKeyMaybe = ks.$1;
                  ks.$2.cancel();
                  return (Option.none(), sub);
                }, ifAbsent: () {
                  oldKeyMaybe = Option.none();
                  return (Option.none(), sub);
                });
                removeKey(e.key, oldKeyMaybe);

              case ChangeRecordDelete<VParent>():
                if (!_mappedKeysSubs.containsKey(e.key)) {
                  // Duplicate deletion from upstream
                  continue;
                }
                final mks = _mappedKeysSubs.remove(e.key)!;
                mks.$2.cancel();
                removeKey(e.key, mks.$1);
            }
          }

          if (keyChanges.isNotEmpty) {
            return KeyChanges(keyChanges.lock);
          } else {
            throw NoValueException();
          }
      }
      // We set memoized to false as this is a change stream merged with another change stream
      // (coming from the group computations - see [_onConvertGroup])
    }, memoized: false);
    ComputedSubscription<ChangeEvent<K, V>>? computedChangesSubscription;
    _changes = MergingChangeStream(
        onListen: () => computedChangesSubscription =
            computedChanges.listen(_changes.add, _changes.addError),
        onCancel: () {
          computedChangesSubscription!.cancel();
          for (var ksub in _mappedKeysSubs.values) {
            ksub.$2.cancel();
          }
          _mappedKeysSubs.clear();
          _mappedKeysReverse.clear();
        });
    changes = $(() => _changes.use);
    snapshot = snapshotComputation(changes, () {
      _setUpstream(_parent.snapshot.use);
      return <K, V>{}.lock;
    });

    _tracker = CSTracker(changes, snapshot);
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
  Computed<bool> get isEmpty =>
      isEmptyExpando[this] ??= $(() => snapshot.use.isEmpty);

  @override
  Computed<bool> get isNotEmpty =>
      isNotEmptyExpando[this] ??= $(() => snapshot.use.isNotEmpty);

  @override
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);
}
