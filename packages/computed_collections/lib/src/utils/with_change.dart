import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../change_event.dart';

extension ChangeEventApplication<K, V> on IMap<K, V> {
  IMap<K, V> withChange(ChangeEvent<K, V> e) => switch (e) {
        KeyChanges(changes: var changes) => changes.entries.fold(
            this,
            (c, change) => switch (change.value) {
                  ChangeRecordValue(value: var v) => c.add(change.key, v),
                  ChangeRecordDelete() => c.remove(change.key),
                }),
        ChangeEventReplace(newCollection: var c) => c,
      };
}
