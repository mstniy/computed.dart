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
}

@immutable
class ChangeRecordInsert<V> extends ChangeRecord<V> {
  final V value;

  ChangeRecordInsert(this.value);

  bool operator ==(Object other) =>
      other is ChangeRecordInsert && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@immutable
class ChangeRecordDelete<V> extends ChangeRecord<V> {
  ChangeRecordDelete();

  bool operator ==(Object other) => other is ChangeRecordDelete;

  @override
  int get hashCode => 0;
}

@immutable
class ChangeRecordUpdate<V> extends ChangeRecord<V> {
  final V newValue;

  ChangeRecordUpdate(this.newValue);

  bool operator ==(Object other) =>
      other is ChangeRecordUpdate && other.newValue == newValue;

  @override
  int get hashCode => newValue.hashCode;
}

@immutable
class ChangeEventReplace<K, V> extends ChangeEvent<K, V> {
  final IMap<K, V> newCollection;

  ChangeEventReplace(this.newCollection);

  bool operator ==(Object other) =>
      other is ChangeEventReplace && other.newCollection == newCollection;

  @override
  int get hashCode => newCollection.hashCode;
}
