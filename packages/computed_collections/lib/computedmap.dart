import 'package:computed/computed.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/imapspy.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:computed/utils/streams.dart';
import 'package:meta/meta.dart';

class _ValueOrException<T> {
  final bool _isValue;
  Object? _exc;
  T? _value;

  _ValueOrException.value(this._value) : _isValue = true;
  _ValueOrException.exc(this._exc) : _isValue = false;

  T get value {
    if (_isValue) return _value as T;
    throw _exc!;
  }
}

/// An in-memory, partially- or fully-observable key-value store.
/// Similar to the ObservableMap from the `observable` package, but with the following upsides:
/// - Individual keys can be observed
/// - Supports immutable snapshots (using fast_immutable_collections)
class ComputedMap<K, V> extends IComputedMap<K, V> {
  late final Computed<IMapSpy<K, V>> _c;
  late final Computed<IMap<K, V>> _snapshot;
  final _cSubs = <ComputedSubscription<IMapSpy<K, V>>>{};
  IMapSpy<K, V> lastPrev;
  _ValueOrException<IMapSpy<K, V>>? curRes;
  // These are set because we create them lazily, and forget about them when they lose all subscribers
  // But they may gain subscribers later in the future, and at that point there might already be
  // (an)other stream(s)/computation(s).
  final _keyChangeStreams = <K, Set<ValueStream<ChangeRecord<K, V>>>>{};
  final _keyChangeStreamComputations = <K, Set<Computed<ChangeRecord<K, V>>>>{};
  final _keyValueStreams = <K, Set<ValueStream<V?>>>{};
  final _keyValueComputations = <K, Set<Computed<V?>>>{};
  ComputedMap(IMapSpy<K, V> Function(IMapSpy<K, V> prev) f,
      {required IMap<K, V> initialPrev,
      bool memoized = true,
      bool async = false})
      : lastPrev = IMapSpy.wrap(initialPrev) {
    _c = Computed.withPrev((prev) {
      lastPrev = prev;
      return f(IMapSpy.wrap(prev.imap));
    },
        initialPrev: IMapSpy.wrap(initialPrev),
        memoized: memoized,
        async: async);
    _snapshot = $(() => _c.use.imap);
  }

  @visibleForTesting
  void fix(IMap<K, V> value) {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.fix(IMapSpy.wrap(value));
  }

  @visibleForTesting
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.fixThrow(e);
  }

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IMap<K, V> Function() mock) => _c.mock(() => IMapSpy.wrap(mock()));

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void unmock() => _c.unmock();

  void _cListenerValue(IMapSpy<K, V> event) {
    curRes = _ValueOrException.value(event);
    if (event is! IMapSpy) {
      // The user f returned a non-spied IMap, we don't know what has changed, so notify all listeners
      _notifyAllKeyStreams();
    } else {
      final ress = event as IMapSpy<K, V>;
      if (!identical(ress.wrapped, lastPrev)) {
        // The user f returned an IMap not related to the previous one, we don't know what has changed, so notify all listeners
        _notifyAllKeyStreams();
      } else {
        _notifyKeyStreams(ress.changedKeys);
      }
    }
  }

  void _cListenerError(Object e) {
    // TODO: Make Computed support passing stacktraces to listeners
    curRes = _ValueOrException.exc(e);
    _notifyAllKeyStreams();
  }

  void _notifyAllKeyStreams() {
    if (curRes!._isValue) {
      for (var entry in curRes!.value.entries) {
        for (var stream in _keyValueStreams[entry.key] ?? <ValueStream<V?>>{}) {
          stream.add(entry.value);
        }
      }
    } else {
      for (var entry in _keyValueStreams.entries) {
        for (var stream in entry.value) {
          stream.addError(curRes!._exc!);
        }
      }
    }
  }

  void _notifyKeyStreams(Iterable<K> keys) {
    for (var key in keys) {
      final value = curRes!.value[key];
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
    late final ComputedSubscription<IMapSpy<K, V>> sub;
    final computation = $(() => stream.use);
    stream = ValueStream<V?>(onListen: () {
      final streams =
          _keyValueStreams.putIfAbsent(key, () => <ValueStream<V?>>{});
      streams.add(stream);
      final computations =
          _keyValueComputations.putIfAbsent(key, () => <Computed<V?>>{});
      computations.add(computation);
      sub = _c.listen(_cListenerValue, _cListenerError);
      _cSubs.add(sub);
    }, onCancel: () {
      final streams = _keyValueStreams[key]!;
      streams.remove(stream);
      final computations = _keyValueComputations[key]!;
      computations.remove(computation);
      sub.cancel();
      _cSubs.remove(sub);
    });

    if (curRes != null) {
      // Seed the stream
      if (curRes!._isValue) {
        stream.add(curRes!.value[key]);
      } else {
        stream.addError(curRes!._exc!);
      }
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
  Computed<IMap<K, V>> get snapshot => _snapshot;

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
