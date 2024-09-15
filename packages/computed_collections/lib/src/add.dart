import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:computed_collections/src/remove.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'utils/cs_tracker.dart';

class AddComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  final K _key;
  final V _value;
  final ComputedMap<K, V> _parent;
  late final CSTracker<K, V> _tracker;
  AddComputedMap(this._parent, this._key, this._value) {
    final parentContainsKey = _parent.containsKey(_key);
    length = $(() => _parent.length.use + (parentContainsKey.use ? 0 : 1));
    snapshot = $(() => _parent.snapshot.use.add(this._key, this._value));
    changes = Computed(() {
      final changeEvent = _parent.changes.use;
      switch (changeEvent) {
        case ChangeEventReplace<K, V>():
          return ChangeEventReplace(
              changeEvent.newCollection.add(_key, _value));
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

  @override
  Computed<V?> operator [](K key) {
    if (key == _key) return $(() => _value);
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
      return RemoveComputedMap(_parent, _key);
    } else {
      return RemoveComputedMap(this, key);
    }
  }

  @override
  Computed<bool> containsKey(K key) {
    if (key == _key) return $(() => true);
    return _parent.containsKey(key);
  }

  @override
  Computed<bool> containsValue(V value) {
    if (value == _value) return $(() => true);
    // Cannot just return _parent.containsValue(value) here - we might overwrite it
    return _tracker.containsValue(value);
  }

  @override
  late final Computed<ChangeEvent<K, V>> changes;
  @override
  late final Computed<IMap<K, V>> snapshot;
  @override
  Computed<bool> get isEmpty => $(() => false);
  @override
  Computed<bool> get isNotEmpty => $(() => true);
  @override
  late final Computed<int> length;
}
