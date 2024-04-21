import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/pubsub.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:meta/meta.dart';

import 'computedmap_mixins.dart';
import 'utils/option.dart';

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
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final IMap<K, V> Function()? _initialValueComputer;
  final Stream<ChangeEvent<K, V>> _stream;
  late final Computed<ChangeEvent<K, V>> _changes;
  late final Computed<IMap<K, V>> _c;
  // The "keep-alive" subscription used by key streams, as we explicitly break the dependency DAG of Computed.
  ComputedSubscription<IMap<K, V>>? _cSub;
  late final PubSub<K, Option<V>> _keyPubSub;
  _ValueOrException<IMap<K, V>>? _curRes;
  ChangeStreamComputedMap(this._stream, [this._initialValueComputer]) {
    _keyPubSub = PubSub<K, Option<V>>((k) {
      // TODO: This never returns Option.none. Maybe remove that functionality from Pubsub again?
      if (_curRes == null) {
        // First subscriber - kickstart the keepalive subscription
        assert(_cSub == null);
        // Escape the Computed zone
        Zone.current.parent!.run(() {
          _cSub = _c.listen((e) {},
              null); //////////////////////////////////////// todo: we need to cancel this onDispose
        });
      }
      final m = _curRes!.value; // Throws if it is an exception
      if (m.containsKey(k))
        return Option.some(Option.some(m[k])); // There is a value
      return Option.some(Option.none()); // We know that there is no value
    });
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
            switch (e.value) {
              case ChangeRecordValue<V>(value: var value):
                keysToNotify.add(key);
                prev = prev.add(key, value);
              case ChangeRecordDelete<V>():
                keysToNotify.add(key);
                prev = prev.remove(key);
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
        // Escape the Computed zone
        Zone.current.parent!.run(_notifyAllKeyStreams);
        throw e;
      });

      if (notifier != null) {
        // Escape the Computed zone
        Zone.current.parent!.run(notifier!);
      }

      return prev;
    }, async: true, initialPrev: firstReactToken);

    isEmpty = $(() => _c.use.isEmpty);
    isNotEmpty = $(() => _c.use.isNotEmpty);
    length = $(() => _c.use.length);
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
  void mock(IComputedMap<K, V> mock) => _c.mock(() {
        try {
          final mockRes = mock.snapshot.use;
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
    if (_curRes!._isValue) {
      final m = _curRes!._value!;
      for (var key in _keyPubSub.subbedKeys) {
        // TODO: This is inefficient, as subbedKeys is already an iterator over the internal pubsub map,
        //  but .pub will do a new search on it.
        //  Also if there are a lot of keys but few subscribers, we do an O(n) loop for nothing. Set intersection might be faster.
        _keyPubSub.pub(
            key, m.containsKey(key) ? Option.some(m[key]) : Option.none());
      }
    } else {
      final e = _curRes!._exc!;
      for (var key in _keyPubSub.subbedKeys) {
        _keyPubSub.pubError(key, e);
      }
    }
  }

  void _notifyKeyStreams(Iterable<K> keys) {
    assert(_curRes!._isValue);
    final m = _curRes!._value!;
    for (var key in keys) {
      // Note that this is a no-op if the key is not subscribed to
      _keyPubSub.pub(
          key, m.containsKey(key) ? Option.some(m[key]) : Option.none());
    }
  }

  Computed<V?> operator [](K key) {
    final keySub = _keyPubSub.sub(key);
    return $(() {
      final keyOption = keySub.use;
      if (keyOption.is_) return keyOption.value;
      return null;
    });
  }

  @override
  Computed<ChangeEvent<K, V>> get changes => _changes;

  @override
  Computed<bool> containsKey(K key) {
    final keySub = _keyPubSub.sub(key);
    return $(() {
      final keyOption = keySub.use;
      return keyOption.is_;
    });
  }

  @override
  // TODO: Cache this with ComputationCache
  Computed<bool> containsValue(V value) => $(() => _c.use.containsValue(value));

  @override
  late final Computed<bool> isEmpty;

  @override
  late final Computed<bool> isNotEmpty;

  @override
  late final Computed<int> length;

  @override
  Computed<IMap<K, V>> get snapshot => _c;
}
