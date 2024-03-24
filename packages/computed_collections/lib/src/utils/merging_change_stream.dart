import 'dart:async';

import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';

class MergingChangeStream<K, V> extends ValueStream<ChangeEvent<K, V>> {
  ChangeEvent<K, V>? _changesLastAdded;
  MergingChangeStream({void Function()? onListen, void Function()? onCancel})
      : super(onListen: onListen, onCancel: onCancel);
  @override
  void add(ChangeEvent<K, V> change) {
    if (_changesLastAdded == null) {
      _changesLastAdded = change;
      scheduleMicrotask(() {
        _changesLastAdded = null;
      });
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
    super.add(_changesLastAdded!);
  }

  // TODO: Logic for "merging" errors with values
}
