import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:computed/utils/streams.dart';
import 'package:meta/meta.dart';

import 'computedmap_mixins.dart';

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

class ChangeStreamComputedMap<K, V>
    with ComputedMapMixin<K, V>
    implements IComputedMap<K, V> {
  final IMap<K, V> Function()? _initialValueComputer;
  final Stream<ChangeEvent<K, V>> _stream;
  late final Computed<ChangeEvent<K, V>> _changes;
  late final Computed<IMap<K, V>> _c;
  // The "keep-alive" subscription used by key streams, as we explicitly break the dependency DAG of Computed.
  ComputedSubscription<IMap<K, V>>? _cSub;
  final _keyValueStreams = <K, Map<ValueStream<V?>, Computed<V?>>>{};
  _ValueOrException<IMap<K, V>>?
      _curRes; // TODO: After adding support for disposing computations to Computed, set this to null as the disposer
  ChangeStreamComputedMap(this._stream, [this._initialValueComputer]) {
    _changes = $(() => _stream.use);
    final firstReactToken = IMap<K,
        V>(); // TODO: This is obviously ugly. Make Computed.withPrev support null instead
    _c = Computed.withPrev((prev) {
      void Function()? notifier;
      if (identical(prev, firstReactToken)) {
        if (_initialValueComputer != null) {
          prev = _initialValueComputer!();
        } else {
          prev = <K, V>{}.lock;
        }

        _curRes = _ValueOrException.value(prev);
        notifier = _notifyAllKeyStreams;
      }
      _stream.react((change) {
        Set<K>? keysToNotify = <K>{}; // If null -> notify all keys
        if (change is ChangeEventReplace<K, V>) {
          keysToNotify = null;
          prev = change.newCollection;
        } else if (change is KeyChanges<K, V>) {
          for (var e in change.changes.entries) {
            final key = e.key;
            final record = e.value;
            if (record is ChangeRecordValue<V>) {
              keysToNotify.add(key);
              prev = prev.add(key, record.value);
            } else if (record is ChangeRecordDelete<V>) {
              keysToNotify.add(key);
              prev = prev.remove(key);
            } else {
              assert(false);
            }
          }
        }

        _curRes = _ValueOrException.value(prev);

        if (keysToNotify == null) {
          // Computed doesn't like it when a computation adds things to a stream,
          // so cheat here once again
          notifier = _notifyAllKeyStreams;
        } else {
          notifier ??= () => _notifyKeyStreams(keysToNotify!);
        }
      }, (e) {
        _curRes = _ValueOrException.exc(e);
        Zone.current.parent!.scheduleMicrotask(_notifyAllKeyStreams);
        throw e;
      });

      if (notifier != null) {
        notifier!();
      }

      return prev;
    }, async: true, initialPrev: firstReactToken);
  }

  @visibleForTesting
  void fix(IMap<K, V> value) {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.fix(value);
    _curRes = _ValueOrException.value(value);
    _notifyAllKeyStreams();
  }

  @visibleForTesting
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.fixThrow(e);
    // TODO: Maybe refactor this logic out? Currently it is duplicated here and in the original computation
    _curRes = _ValueOrException.exc(e);
    _notifyAllKeyStreams();
  }

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IMap<K, V> Function() mock) => _c.mock(() {
        try {
          final mockRes = mock();
          _curRes = _ValueOrException.value(mockRes);
        } on NoValueException {
          rethrow; // Propagate
        } catch (e) {
          _curRes = _ValueOrException.exc(e);
        }
        _notifyAllKeyStreams();
        return _curRes!
            .value; // Will throw if there was an exception, which is fine
      });

  @visibleForTesting
  void unmock() {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.unmock(); // Note that this won't notify key streams
    _notifyAllKeyStreams();
  }

  void _notifyAllKeyStreams() {
    for (var entry in _keyValueStreams.entries) {
      final value = _curRes!._isValue ? _curRes!.value[entry.key] : null;
      for (var stream in entry.value.keys) {
        if (_curRes!._isValue) {
          stream.add(value);
        } else {
          stream.addError(_curRes!._exc!);
        }
      }
    }
  }

  void _notifyKeyStreams(Iterable<K> keys) {
    assert(_curRes!._isValue);
    for (var key in keys) {
      final value = _curRes!._value![key];
      for (var stream in _keyValueStreams[key]?.keys ?? <ValueStream<V?>>[]) {
        stream.add(value);
      }
    }
  }

  Computed<V?> operator [](K key) {
    // If there is an existing (cached) computation, return it
    final streams = _keyValueStreams[key];
    if (streams != null) return streams.values.first;

    // Otherwise, create a new stream-computation pair and subscribe to the user computation
    late final ValueStream<V?> stream;
    final computation = $(() => stream.use);
    stream = ValueStream<V?>(
        sync: true, // TODO: Audit the sync stream
        onListen: () {
          final streams = _keyValueStreams.putIfAbsent(
              key, () => <ValueStream<V?>, Computed<V?>>{});
          streams[stream] = computation;
          _cSub ??= _c.listen((e) {}, null);
        },
        onCancel: () {
          final streams = _keyValueStreams[key]!;
          streams.remove(stream);
          if (streams.isEmpty) {
            _keyValueStreams.remove(key);
          }
          if (_keyValueStreams.isEmpty) {
            _cSub!.cancel();
            _cSub = null;
          }
        });

    // Seed the stream
    if (_curRes != null) {
      if (_curRes!._isValue) {
        stream.add(_curRes!.value[key]);
      } else {
        stream.addError(_curRes!._exc!);
      }
    } else {
      stream.add(null);
    }

    return computation;
  }

  @override
  Computed<ChangeEvent<K, V>> get changes => _changes;

  @override
  Computed<bool> containsKey(K key) => $(() => _c.use.containsKey(key));

  @override
  Computed<bool> containsValue(V value) => $(() => _c.use.containsValue(value));

  @override
  Computed<bool> get isEmpty => $(() => _c.use.isEmpty);

  @override
  Computed<bool> get isNotEmpty => $(() => _c.use.isNotEmpty);

  @override
  Computed<int> get length => $(() => _c.use.length);

  @override
  Computed<IMap<K, V>> get snapshot => _c;
}
