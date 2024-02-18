import 'package:computed/computed.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:computed/utils/streams.dart';
import 'package:meta/meta.dart';

class ChangeStreamComputedMap<K, V> implements IComputedMap<K, V> {
  final Computed<Set<ChangeRecord<K, V>>> _stream;
  late final Computed<IMap<K, V>> _c;
  // The "keep-alive" subscription used by key streams, as we explicitly break the dependency DAG of Computed.
  ComputedSubscription<IMap<K, V>>? _cSub;
  // These are set because we create them lazily, and forget about them when they lose all subscribers
  // But they may gain subscribers later in the future, and at that point there might already be
  // (an)other stream(s)/computation(s).
  final _keyChangeStreams = <K, Set<ValueStream<ChangeRecord<K, V>>>>{};
  final _keyChangeStreamComputations = <K, Set<Computed<ChangeRecord<K, V>>>>{};
  final _keyValueStreams =
      <K, Set<ValueStream<V?>>>{}; // TODO: Store these in a single collection
  final _keyValueComputations = <K, Set<Computed<V?>>>{};
  Set<ChangeRecord<K, V>>? _lastChange;
  IMap<K, V>?
      _curRes; // TODO: After adding support for disposing computations to Computed, set this to null as the disposer
  ChangeStreamComputedMap(this._stream) {
    _c = Computed.withPrev((prev) {
      Set<ChangeRecord<K, V>> changes;
      try {
        changes = _stream.use;
      } on NoValueException {
        // No changes
        return prev;
      }
      Set<K>? keysToNotify = <K>{}; // If null -> notify all listeners
      for (var change in changes) {
        if (change is ChangeRecordInsert<K, V>) {
          keysToNotify?.add(change.key);
          prev = prev.add(change.key, change.value);
        } else if (change is ChangeRecordUpdate<K, V>) {
          keysToNotify?.add(change.key);
          prev = prev.add(change.key, change.newValue);
        } else if (change is ChangeRecordDelete<K, V>) {
          keysToNotify?.add(change.key);
          prev = prev.remove(change.key);
        } else if (change is ChangeRecordReplace<K, V>) {
          keysToNotify = null;
          prev = change.newCollection;
        } else {
          assert(false);
        }
      }

      _curRes = prev;

      if (!identical(changes, _lastChange)) {
        // We cheat here a bit to avoid notifying listeners a second time
        //  in case Computed runs us twice (eg. in debug mode)
        _lastChange = changes;
        if (keysToNotify == null) {
          _notifyAllKeyStreams();
        } else {
          _notifyKeyStreams(keysToNotify);
        }
      }

      return prev;
    }, initialPrev: <K, V>{}.lock);
  }

  @visibleForTesting
  void fix(IMap<K, V> value) {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.fix(value);
  }

  @visibleForTesting
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.fixThrow(e);
  }

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IMap<K, V> Function() mock) => _c.mock(mock);

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void unmock() => _c.unmock();

  void _notifyAllKeyStreams() {
    for (var entry in _curRes!.entries) {
      for (var stream in _keyValueStreams[entry.key] ?? <ValueStream<V?>>{}) {
        stream.add(entry.value);
      }
    }
  }

  void _notifyKeyStreams(Iterable<K> keys) {
    for (var key in keys) {
      final value = _curRes![key];
      for (var stream in _keyValueStreams[key] ?? <ValueStream<V?>>{}) {
        stream.add(value);
      }
    }
  }

  Computed<V?> operator [](K key) {
    // If there is an existing (cached) computation, return it
    final computations =
        _keyValueComputations.putIfAbsent(key, () => <Computed<V?>>{});
    if (computations.isNotEmpty) return computations.first;

    // As there is a strict one-to-one correspondence between streams and computations,
    // we expect this to hold
    assert(!_keyValueStreams.containsKey(key));

    // Otherwise, create a new stream-computation pair and subscribe to the user computation
    late final ValueStream<V?> stream;
    final computation = $(() => stream.use);
    stream = ValueStream<V?>(
        sync: true,
        onListen: () {
          final streams =
              _keyValueStreams.putIfAbsent(key, () => <ValueStream<V?>>{});
          streams.add(stream);
          final computations =
              _keyValueComputations.putIfAbsent(key, () => <Computed<V?>>{});
          computations.add(computation);
          _cSub ??= _c.listen((e) {}, null);
        },
        onCancel: () {
          final streams = _keyValueStreams[key]!;
          streams.remove(stream);
          if (streams.isEmpty) {
            _keyValueStreams.remove(key);
          }
          final computations = _keyValueComputations[key]!;
          computations.remove(computation);
          if (computations.isEmpty) {
            _keyValueComputations.remove(key);
          }
          if (_keyValueComputations.isEmpty) {
            _cSub!.cancel();
            _cSub = null;
          }
        });

    // Seed the stream
    if (_curRes != null) {
      stream.add(_curRes![key]);
    } else {
      // Note that this might be (quickly) overwritten if there is already a change stream event
      stream.add(null);
    }

    return computation;
  }

  @override
  IComputedMap<K, V> addAll(IMap<K, V> other) {
    // TODO: implement addAll
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> addAllComputed(IComputedMap<K, V> other) {
    // TODO: implement addAllComputed
    throw UnimplementedError();
  }

  @override
  IComputedMap<RK, RV> cast<RK, RV>() {
    // TODO: implement cast
    throw UnimplementedError();
  }

  @override
  // TODO: implement changes
  Computed<ChangeRecord<K, V>> get changes => throw UnimplementedError();

  @override
  Computed<ChangeRecord<K, V>> changesFor(K key) {
    // TODO: implement changesFor
    throw UnimplementedError();
  }

  @override
  Computed<bool> containsKey(K key) {
    // TODO: implement containsKey
    throw UnimplementedError();
  }

  @override
  Computed<bool> containsValue(V value) {
    // TODO: implement containsValue
    throw UnimplementedError();
  }

  @override
  // TODO: implement isEmpty
  Computed<bool> get isEmpty => throw UnimplementedError();

  @override
  // TODO: implement isNotEmpty
  Computed<bool> get isNotEmpty => throw UnimplementedError();

  @override
  // TODO: implement length
  Computed<int> get length => throw UnimplementedError();

  @override
  IComputedMap<K2, V2> map<K2, V2>(
      MapEntry<K2, V2> Function(K key, V Value) convert) {
    // TODO: implement map
    throw UnimplementedError();
  }

  @override
  IComputedMap<K2, V2> mapComputed<K2, V2>(
      Computed<MapEntry<K2, V2>> Function(K key, V Value) convert) {
    // TODO: implement mapComputed
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V2> mapValues<V2>(V2 Function(K key, V Value) convert) {
    // TODO: implement mapValues
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V2> mapValuesComputed<V2>(
      Computed<V2> Function(K key, V Value) convert) {
    // TODO: implement mapValuesComputed
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> putIfAbsent(K key, V Function() ifAbsent) {
    // TODO: implement putIfAbsent
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> remove(K key) {
    // TODO: implement remove
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> removeWhere(bool Function(K key, V value) test) {
    // TODO: implement removeWhere
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> removeWhereComputed(
      Computed<bool> Function(K key, V value) test) {
    // TODO: implement removeWhereComputed
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> replace(K key, V value) {
    // TODO: implement replace
    throw UnimplementedError();
  }

  @override
  Computed<IMap<K, V>> get snapshot => _c;

  @override
  IComputedMap<K, V> update(K key, V Function(V value) update,
      {V Function()? ifAbsent}) {
    // TODO: implement update
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> updateAll(V Function(K key, V Value) update) {
    // TODO: implement updateAll
    throw UnimplementedError();
  }

  @override
  IComputedMap<K, V> updateAllComputed(
      Computed<V> Function(K key, V Value) update) {
    // TODO: implement updateAllComputed
    throw UnimplementedError();
  }
}
