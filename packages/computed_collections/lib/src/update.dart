import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:computed_collections/src/expandos.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'utils/cs_tracker.dart';

class UpdateComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  final K _key;
  final V Function(V value) _update;
  final V Function()? _ifAbsent;
  final ComputedMap<K, V> _parent;
  late final CSTracker<K, V> _tracker;

  late final Computed<V> _keyComputation;

  Never _throwArgError() =>
      throw ArgumentError.value(_key, "key", "Key not in map.");

  UpdateComputedMap(this._parent, this._key, this._update, this._ifAbsent) {
    final parentContainsKey = _parent.containsKey(_key);
    length = _ifAbsent != null
        ? $(() => _parent.length.use + (parentContainsKey.use ? 0 : 1))
        : $(() {
            if (parentContainsKey.use) {
              return _parent.length.use;
            }
            _throwArgError();
          });
    // This allows us to share the computation of the user function
    //  between snapshot and operator[]
    _keyComputation = _getKeyComputation();
    snapshot = $(() => _parent.snapshot.use.add(_key, _keyComputation.use));
    changes = Computed(() {
      final changeEvent = _parent.changes.use;
      switch (changeEvent) {
        case ChangeEventReplace<K, V>():
          return ChangeEventReplace(changeEvent.newCollection
              .update(_key, _update, ifAbsent: _ifAbsent));
        case KeyChanges<K, V>():
          final changes =
              changeEvent.changes.entries.map((upstreamChange) => MapEntry(
                  upstreamChange.key,
                  upstreamChange.key == _key
                      ? switch (upstreamChange.value) {
                          ChangeRecordValue<V>(value: final v) =>
                            ChangeRecordValue(_update(v)),
                          ChangeRecordDelete<V>() => _ifAbsent != null
                              ? ChangeRecordValue(_ifAbsent!())
                              : _throwArgError()
                        }
                      : upstreamChange.value));
          if (changes.isEmpty) throw NoValueException();
          return KeyChanges(IMap.fromEntries(changes));
      }
    }, assertIdempotent: false);
    _tracker = CSTracker(changes, snapshot);
  }

  Computed<V> _getKeyComputation() {
    final parentContainsKey = _parent.containsKey(_key);
    final parentValue = _parent[_key];
    return Computed(() {
      if (parentContainsKey.use) {
        return _update(parentValue.use as V);
      }
      if (_ifAbsent != null) {
        return _ifAbsent!();
      }
      _throwArgError();
    }, assertIdempotent: false);
  }

  @override
  Computed<V?> operator [](K key) {
    if (key != _key) return _parent[key];
    return _keyComputation;
  }

  @override
  Computed<bool> containsKey(K key) {
    if (key != _key) return _parent.containsKey(key);
    // We ignore the possibility that _ifAbsent() or _update might throw
    //  to avoid having to run them.
    if (_ifAbsent != null) return $(() => true);
    final parentContainsKey = _parent.containsKey(key);
    return $(() => parentContainsKey.use ? true : _throwArgError());
  }

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  late final Computed<ChangeEvent<K, V>> changes;
  @override
  late final Computed<IMap<K, V>> snapshot;
  @override
  Computed<bool> get isEmpty {
    if (_ifAbsent != null) return $(() => false);
    if (isEmptyExpando[this] != null) return isEmptyExpando[this]!;
    final parentContainsKey = _parent.containsKey(_key);
    return isEmptyExpando[this] =
        $(() => parentContainsKey.use ? false : _throwArgError());
  }

  @override
  Computed<bool> get isNotEmpty {
    if (_ifAbsent != null) return $(() => true);
    if (isNotEmptyExpando[this] != null) return isNotEmptyExpando[this]!;
    final parentContainsKey = _parent.containsKey(_key);
    return isNotEmptyExpando[this] =
        $(() => parentContainsKey.use ? true : _throwArgError());
  }

  @override
  late final Computed<int> length;
}
