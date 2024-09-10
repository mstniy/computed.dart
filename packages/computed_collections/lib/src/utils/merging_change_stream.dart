import 'dart:async';

import 'package:computed_collections/change_event.dart';

class MergingChangeStream<K, V> extends Stream<ChangeEvent<K, V>> {
  ChangeEvent<K, V>? _changesLastAdded;
  final StreamController<ChangeEvent<K, V>> _stream;
  MergingChangeStream({void Function()? onListen, void Function()? onCancel})
      : _stream = StreamController.broadcast(
            sync: true, onListen: onListen, onCancel: onCancel);

  void _maybeFlushChanges() {
    if (_changesLastAdded == null) return; // Already flushed
    final oldChangesLastAdded = _changesLastAdded!;
    _changesLastAdded = null;
    _stream.add(oldChangesLastAdded);
  }

  void add(ChangeEvent<K, V> change) {
    if (_changesLastAdded == null) {
      // If the given change is empty, do nothing
      if (change is! KeyChanges<K, V> || change.changes.isNotEmpty) {
        _changesLastAdded = change;
        // Batch the changes until the next microtask, then add to the stream
        scheduleMicrotask(_maybeFlushChanges);
      }
    } else {
      _changesLastAdded = switch (change) {
        ChangeEventReplace<K, V>() => change,
        KeyChanges<K, V>() => switch (_changesLastAdded!) {
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
      };
    }
  }

  void addError(Object o) {
    // TODO: Do not flush synchronously here.
    //  Follow the pattern used by [add].
    _maybeFlushChanges();
    _stream.addError(o);
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
