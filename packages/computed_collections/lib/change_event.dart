import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

@immutable
sealed class ChangeEvent<K, V> {
  ChangeEvent();
}

@immutable
sealed class ChangeRecord<V> {
  ChangeRecord();
}

@immutable
class KeyChanges<K, V> extends ChangeEvent<K, V> {
  final IMap<K, ChangeRecord<V>> changes;

  KeyChanges(this.changes);

  @override
  bool operator ==(Object other) =>
      other is KeyChanges && other.changes == changes;

  @override
  int get hashCode => changes.hashCode;

  @override
  String toString() => 'KeyChanges(${changes.toString()})';
}

@immutable
class ChangeRecordValue<V> extends ChangeRecord<V> {
  final V value;

  ChangeRecordValue(this.value);

  @override
  bool operator ==(Object other) =>
      other is ChangeRecordValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ChangeRecordValue(${value.toString()})';
}

@immutable
class ChangeRecordDelete<V> extends ChangeRecord<V> {
  ChangeRecordDelete();

  @override
  bool operator ==(Object other) => other is ChangeRecordDelete;

  @override
  int get hashCode => 0;
}

@immutable
class ChangeEventReplace<K, V> extends ChangeEvent<K, V> {
  final IMap<K, V> newCollection;

  ChangeEventReplace(this.newCollection);

  @override
  bool operator ==(Object other) =>
      other is ChangeEventReplace && other.newCollection == newCollection;

  @override
  int get hashCode => newCollection.hashCode;

  @override
  String toString() => 'ChangeEventReplace(${newCollection.toString()})';
}

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
