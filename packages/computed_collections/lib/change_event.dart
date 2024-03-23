import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

@immutable
abstract class ChangeEvent<K, V> {
  ChangeEvent();
}

@immutable
abstract class ChangeRecord<V> {
  ChangeRecord();
}

@immutable
class KeyChanges<K, V> extends ChangeEvent<K, V> {
  final IMap<K, ChangeRecord<V>> changes;

  KeyChanges(this.changes);

  bool operator ==(Object other) =>
      other is KeyChanges && other.changes == changes;

  @override
  int get hashCode => changes.hashCode;

  @override
  String toString() => changes.toString();
}

@immutable
class ChangeRecordValue<V> extends ChangeRecord<V> {
  final V value;

  ChangeRecordValue(this.value);

  bool operator ==(Object other) =>
      other is ChangeRecordValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value.toString();
}

@immutable
class ChangeRecordDelete<V> extends ChangeRecord<V> {
  ChangeRecordDelete();

  bool operator ==(Object other) => other is ChangeRecordDelete;

  @override
  int get hashCode => 0;
}

@immutable
class ChangeEventReplace<K, V> extends ChangeEvent<K, V> {
  final IMap<K, V> newCollection;

  ChangeEventReplace(this.newCollection);

  bool operator ==(Object other) =>
      other is ChangeEventReplace && other.newCollection == newCollection;

  @override
  int get hashCode => newCollection.hashCode;

  @override
  String toString() => newCollection.toString();
}
