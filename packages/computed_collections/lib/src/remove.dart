import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'add_computedmap.dart';
import 'computedmap_mixins.dart';
import 'utils/cs_tracker.dart';

class RemoveComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  K _key;
  final ComputedMap<K, V> _parent;
  late final CSTracker<K, V> _tracker;
  RemoveComputedMap(this._parent, this._key) {
    final parentContainsKey = _parent.containsKey(_key);
    length = $(() => _parent.length.use - (parentContainsKey.use ? 1 : 0));
    snapshot = $(() => _parent.snapshot.use.remove(this._key));
    changes = Computed(() {
      final changeEvent = _parent.changes.use;
      switch (changeEvent) {
        case ChangeEventReplace<K, V>():
          return ChangeEventReplace(changeEvent.newCollection.remove(_key));
        case KeyChanges<K, V>():
          final changes = changeEvent.changes.entries.map((upstreamChange) {
            if (upstreamChange.key == _key) {
              return <MapEntry<K, ChangeRecord<V>>>[];
            }
            return [upstreamChange];
          }).expand((e) => e);
          if (changes.isEmpty) throw NoValueException();
          return KeyChanges(IMap.fromEntries(changes));
      }
    });
    _tracker = CSTracker(changes, snapshot);
  }

  Computed<V?> operator [](K key) {
    if (key == _key) return $(() => null);
    return _parent[key];
  }

  @override
  ComputedMap<K, V> add(K key, V value) {
    if (key == _key) {
      return AddComputedMap(_parent, key, value);
    } else {
      return AddComputedMap(this, key, value);
    }
  }

  @override
  ComputedMap<K, V> remove(K key) {
    if (key == _key) {
      return this;
    } else {
      return RemoveComputedMap(this, key);
    }
  }

  @override
  Computed<bool> containsKey(K key) {
    if (key == _key) return $(() => false);
    return _parent.containsKey(key);
  }

  @override
  Computed<bool> containsValue(V value) {
    // Cannot just return _parent.containsValue(value) here - _key might be the one that contains it
    return _tracker.containsValue(value);
  }

  late final Computed<ChangeEvent<K, V>> changes;
  late final Computed<IMap<K, V>> snapshot;
  Computed<bool> get isEmpty => $(() => length.use == 0);
  Computed<bool> get isNotEmpty => $(() => length.use > 0);
  late final Computed<int> length;
}
