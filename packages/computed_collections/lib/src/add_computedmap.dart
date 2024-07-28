import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'utils/pubsub.dart';

class AddComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  K _key;
  V _value;
  final IComputedMap<K, V> _parent;
  late final PubSub<K, V> _pubSub;
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
    _pubSub = PubSub(changes, snapshot);
  }

  Computed<V?> operator [](K key) {
    if (key == _key) return $(() => _value);
    return _parent[key];
  }

  @override
  IComputedMap<K, V> add(K key, V value) {
    if (key == _key) {
      return AddComputedMap(_parent, key, value);
    } else {
      return AddComputedMap(this, key, value);
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
    return _pubSub.containsValue(value);
  }

  late final Computed<ChangeEvent<K, V>> changes;
  late final Computed<IMap<K, V>> snapshot;
  Computed<bool> get isEmpty => $(() => false);
  Computed<bool> get isNotEmpty => $(() => true);
  late final Computed<int> length;
}
