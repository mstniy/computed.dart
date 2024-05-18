import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/pubsub.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:meta/meta.dart';

import 'computedmap_mixins.dart';
import 'utils/option.dart';
import 'utils/value_or_exception.dart';

class ChangeStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final IMap<K, V> Function()? _initialValueComputer;
  // TODO: We can probably change this to be a computation once we have .react on computations
  final Stream<ChangeEvent<K, V>> _stream;
  late final Computed<IMap<K, V>> _c;
  // The "keep-alive" subscription used by key streams, as we explicitly break the dependency DAG of Computed.
  ComputedSubscription<IMap<K, V>>? _cSub;
  late final PubSub<K, Option<V>> _keyPubSub;
  ValueOrException<IMap<K, V>>? _curRes;
  ChangeStreamComputedMap(this._stream, [this._initialValueComputer]) {
    _keyPubSub = PubSub<K, Option<V>>((k) {
      final m = _curRes!.value; // Throws if there is an exception
      if (m.containsKey(k)) return Option.some(m[k]); // There is a value
      return Option.none(); // There is no value
    }, () {
      assert(_cSub == null);
      // Kickstart the keepalive subscription
      // Escape the Computed zone
      Zone.current.parent!.run(() {
        _cSub = _c.listen((e) {}, null);
      });
    }, () {
      _cSub!.cancel();
      _cSub = null;
    });
    changes = $(() => _stream.use);
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

        _curRes = ValueOrException.value(prev);
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

        _curRes = ValueOrException.value(prev);

        if (keysToNotify == null) {
          // Computed doesn't like it when a computation adds things to a stream,
          // so cheat here once again
          notifier = _notifyAllKeyStreams;
        } else {
          notifier ??= () => _notifyKeyStreams(keysToNotify!);
        }
      }, (e) {
        _curRes = ValueOrException.exc(e);
        _notifyAllKeyStreams();
        throw e;
      });

      if (notifier != null) {
        notifier!();
      }

      return prev;
    }, async: true, initialPrev: firstReactToken);

    // We do not directly expose _c because it also does bookkeeping, and
    // that would get messes up if it gets mocked.
    snapshot = $(() => _c.use);
    isEmpty = $(() => _c.use.isEmpty);
    isNotEmpty = $(() => _c.use.isNotEmpty);
    length = $(() => _c.use.length);
  }

  @visibleForTesting
  void fix(IMap<K, V> value) {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.fix(value);
    _curRes = ValueOrException.value(value);
    _notifyAllKeyStreams();
  }

  @visibleForTesting
  void fixThrow(Object e) {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.fixThrow(e);
    // TODO: Maybe refactor this logic out? Currently it is duplicated here and in the original computation
    _curRes = ValueOrException.exc(e);
    _notifyAllKeyStreams();
  }

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void mock(IComputedMap<K, V> mock) => _c.mock(() {
        try {
          final mockRes = mock.snapshot.use;
          _curRes = ValueOrException.value(mockRes);
        } on NoValueException {
          rethrow; // Propagate
        } catch (e) {
          _curRes = ValueOrException.exc(e);
        }
        _notifyAllKeyStreams();
        return _curRes!
            .value; // Will throw if there was an exception, which is fine
      });

  @visibleForTesting
  void unmock() {
    // ignore: invalid_use_of_visible_for_testing_member
    _c.unmock(); // Note that this will notify key streams
  }

  void _notifyAllKeyStreams() {
    if (_curRes!.isValue) {
      _keyPubSub.recomputeAllKeys();
    } else {
      _keyPubSub.pubError(_curRes!.exc_!);
    }
  }

  void _notifyKeyStreams(Set<K> keys) {
    assert(_curRes!.isValue);
    _keyPubSub.recomputeKeys(keys);
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
  Computed<bool> containsKey(K key) {
    final keySub = _keyPubSub.sub(key);
    return $(() {
      final keyOption = keySub.use;
      return keyOption.is_;
    });
  }

  final _containsValueCache = ComputationCache<V, bool>();

  @override
  Computed<bool> containsValue(V value) =>
      _containsValueCache.wrap(value, () => _c.use.containsValue(value));

  @override
  late final Computed<ChangeEvent<K, V>> changes;

  @override
  late final Computed<bool> isEmpty;

  @override
  late final Computed<bool> isNotEmpty;

  @override
  late final Computed<int> length;

  @override
  late final Computed<IMap<K, V>> snapshot;
}
