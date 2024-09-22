import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// Represents a change on a map.
@immutable
sealed class ChangeEvent<K, V> {
  ChangeEvent();
}

/// Represent a change on one key of a map.
@immutable
sealed class ChangeRecord<V> {
  ChangeRecord();
}

/// Describes how the keys of a map were changed.
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

/// Describes the new value of one key of a map.
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

/// Describes that this key, if it existed, was deleted.
@immutable
class ChangeRecordDelete<V> extends ChangeRecord<V> {
  ChangeRecordDelete();

  @override
  bool operator ==(Object other) => other is ChangeRecordDelete;

  @override
  int get hashCode => 0;
}

/// Describes that the map was entirely replaced.
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
