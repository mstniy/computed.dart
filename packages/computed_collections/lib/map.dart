import 'dart:async';

import 'package:computed/computed.dart';
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
class ComputedIMap<K, V> {
  late final Computed<IMap<K, V>> _c;
  IMap<K, V> lastPrev;
  _ValueOrException<IMap<K, V>>? curRes;
  final _listeners = <ComputedSubscription<IMap<K, V>>>{};
  final _keyStreams = <K, Set<ValueStream<V?>>>{};
  ComputedIMap(IMap<K, V> Function(IMap<K, V> prev) f,
      {required IMap<K, V> initialPrev,
      bool memoized = true,
      bool async = false})
      : lastPrev = initialPrev {
    _c = Computed.withPrev((prev) {
      lastPrev = prev;
      return f(IMapSpy.wrap(prev));
    }, initialPrev: initialPrev, memoized: memoized, async: async);
  }

  ComputedSubscription<IMap<K, V>> listen(
      void Function(T event)? onData, Function? onError) {
    /*_fsub = _c.listen((res) {
      curRes = _ValueOrException.value(res);
      if (res is! IMapSpy) {
        // The user f returned a non-spied IMap, we don't know what has changed, so notify all listeners
        _notifyAllKeyStreams();
      } else {
        final ress = res as IMapSpy<K, V>;
        if (!identical(ress.wrapped, lastPrev)) {
          // The user f returned an IMap not related to the previous one, we don't know what has changed, so notify all listeners
          _notifyAllKeyStreams();
        } else {
          _notifyKeyStreams(ress.changedKeys);
        }
      }
    }, (e) {
      // TODO: Make Computed support passing stacktraces to listeners
      curRes = _ValueOrException.exc(e);
      _notifyAllKeyStreams();
    }); */
    // TODO: Wrap the user's onData and onError here and hijack them to update our keystreams
    // TODO: Make sure not to do it multiple times if there are multiple listeners
    final sub = _c.listen(onData, onError);
    _listeners.add(sub);
    return sub; // TODO: how will we know when it gets cancelled?
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

  IMap<K, V> get use => _c.use;
  IMap<K, V> useOr(IMap<K, V> value) => _c.useOr(value);
  IMap<K, V> get prev => _c.prev;

  void _notifyAllKeyStreams() {
    if (curRes!._isValue) {
      for (var entry in curRes!.value.entries) {
        for (var stream in _keyStreams[entry.key] ?? <ValueStream<V?>>{}) {
          stream.add(entry.value);
        }
      }
    } else {
      for (var entry in _keyStreams.entries) {
        for (var stream in entry.value) {
          stream.addError(curRes!._exc!);
        }
      }
    }
  }

  void _notifyKeyStreams(Iterable<K> keys) {
    for (var key in keys) {
      final value = curRes!.value[key];
      for (var stream in _keyStreams[key] ?? <ValueStream<V?>>{}) {
        stream.add(value);
      }
    }
  }

  Stream<V?> operator [](K key) {
    final streams = _keyStreams.putIfAbsent(key, () => <ValueStream<V?>>{});
    late ValueStream<V?> stream;
    stream = streams.isNotEmpty
        ? streams.first
        : ValueStream<V?>.seeded(curRes!.value[key], onListen: () {
            final streams =
                _keyStreams.putIfAbsent(key, () => <ValueStream<V?>>{});
            streams.add(stream);
          }, onCancel: () {
            final streams = _keyStreams[key]!;
            streams.remove(stream);
          });
    return stream;
  }
}
