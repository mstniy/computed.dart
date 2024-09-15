import 'dart:async';

import '../../change_event.dart';
import 'value_or_exception.dart';

class MergingChangeStream<K, V> extends Stream<ChangeEvent<K, V>> {
  ValueOrException<ChangeEvent<K, V>>? _changesLastAdded;
  final StreamController<ChangeEvent<K, V>> _stream;
  MergingChangeStream({void Function()? onListen, void Function()? onCancel})
      : _stream = StreamController.broadcast(
            sync: true, onListen: onListen, onCancel: onCancel);

  void _flushChanges() {
    final oldChangesLastAdded = _changesLastAdded!;
    _changesLastAdded = null;
    switch (oldChangesLastAdded) {
      case Value<ChangeEvent<K, V>>(value: final changes):
        _stream.add(changes);
      case Exception<ChangeEvent<K, V>>(exc: final exc):
        _stream.addError(exc);
    }
  }

  void add(ChangeEvent<K, V> change) {
    switch (_changesLastAdded) {
      case null:
        // If the given change is empty, do nothing
        if (change is! KeyChanges<K, V> || change.changes.isNotEmpty) {
          _changesLastAdded = ValueOrException.value(change);
          // Batch the changes until the next microtask, then add to the stream
          scheduleMicrotask(_flushChanges);
        }
      case Value<ChangeEvent<K, V>>(value: final changesLastAdded):
        _changesLastAdded = ValueOrException.value(switch (change) {
          ChangeEventReplace<K, V>() => change,
          KeyChanges<K, V>() => switch (changesLastAdded) {
              KeyChanges<K, V>(changes: final changes) =>
                KeyChanges(changes.addAll(change.changes)),
              ChangeEventReplace<K, V>(newCollection: final oldNewCollection) =>
                ChangeEventReplace(change.changes.entries.fold(
                    oldNewCollection,
                    (newCollection, changeEntry) => switch (changeEntry.value) {
                          ChangeRecordValue<V>(value: final value) =>
                            newCollection.add(changeEntry.key, value),
                          ChangeRecordDelete<V>() =>
                            newCollection.remove(changeEntry.key),
                        })),
            },
        });
      case Exception<ChangeEvent<K, V>>():
      // Ignore changes added after an exception
    }
  }

  void addError(Object o) {
    // Maybe schedule a new MT to notify the listeners
    if (_changesLastAdded == null) {
      scheduleMicrotask(_flushChanges);
    }
    // Overwrite the buffered changes with the exception
    _changesLastAdded = ValueOrException.exc(o);
  }

  @override
  StreamSubscription<ChangeEvent<K, V>> listen(
          void Function(ChangeEvent<K, V> event)? onData,
          {Function? onError,
          void Function()? onDone,
          bool? cancelOnError}) =>
      _stream.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}
