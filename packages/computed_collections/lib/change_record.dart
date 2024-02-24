import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

@immutable
class ChangeRecord<K, V> {
  ChangeRecord();
}

@immutable
class ChangeRecordInsert<K, V> extends ChangeRecord<K, V> {
  final K key;
  final V value;

  ChangeRecordInsert(this.key, this.value);

  // We deliberately don't check the generic types here, as in Dart
  // eg. (List<int> is List<int?>) holds, but not the other way around,
  // making the equality operator asymmetric, unless we go the extra
  // mile of checking in the reverse direction.
  bool operator ==(Object other) =>
      other is ChangeRecordInsert && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);
}

@immutable
class ChangeRecordDelete<K, V> extends ChangeRecord<K, V> {
  final K key;
  final V oldValue;

  ChangeRecordDelete(this.key, this.oldValue);

  bool operator ==(Object other) =>
      other is ChangeRecordDelete &&
      other.key == key &&
      other.oldValue == oldValue;

  @override
  int get hashCode => Object.hash(key, oldValue);
}

@immutable
class ChangeRecordUpdate<K, V> extends ChangeRecord<K, V> {
  final K key;
  final V oldValue, newValue;

  ChangeRecordUpdate(this.key, this.oldValue, this.newValue);

  bool operator ==(Object other) =>
      other is ChangeRecordUpdate &&
      other.key == key &&
      other.oldValue == oldValue &&
      other.newValue == newValue;

  @override
  int get hashCode => Object.hash(key, oldValue, newValue);
}

@immutable
class ChangeRecordReplace<K, V> extends ChangeRecord<K, V> {
  final IMap<K, V> newCollection;

  ChangeRecordReplace(this.newCollection);

  bool operator ==(Object other) =>
      other is ChangeRecordReplace && other.newCollection == newCollection;

  @override
  int get hashCode => newCollection.hashCode;
}
