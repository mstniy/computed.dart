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
      _changesLastAdded = change;
      // Batch the changes until the next microtask, then add to the stream
      scheduleMicrotask(_maybeFlushChanges);
    } else if (change is ChangeEventReplace<K, V>) {
      _changesLastAdded = change;
    } else {
      assert(change is KeyChanges<K, V>);
      if (_changesLastAdded is KeyChanges<K, V>) {
        _changesLastAdded = KeyChanges((_changesLastAdded as KeyChanges<K, V>)
            .changes
            .addAll((change as KeyChanges<K, V>).changes));
      } else {
        assert(_changesLastAdded is ChangeEventReplace<K, V>);
        final keyChanges = (change as KeyChanges<K, V>).changes;
        final keyDeletions =
            keyChanges.entries.where((e) => e.value is ChangeRecordDelete<K>);
        _changesLastAdded = ChangeEventReplace((_changesLastAdded
                as ChangeEventReplace<K, V>)
            .newCollection
            .addEntries(keyChanges.entries
                .where((e) => e.value is! ChangeRecordDelete<K>)
                .map((e) =>
                    MapEntry(e.key, (e.value as ChangeRecordValue<V>).value))));
        keyDeletions.forEach((e) => _changesLastAdded = ChangeEventReplace(
            (_changesLastAdded as ChangeEventReplace<K, V>)
                .newCollection
                .remove(e.key)));
      }
    }
  }

  void addError(Object o) {
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
