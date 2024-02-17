import 'package:meta/meta.dart';

@immutable
class ChangeRecord<K, V> {
  final K key;

  ChangeRecord(this.key);
}

@immutable
class ChangeRecordInsert<K, V> extends ChangeRecord<K, V> {
  final V value;

  ChangeRecordInsert(K key, this.value) : super(key);
}

@immutable
class ChangeRecordDelete<K, V> extends ChangeRecord<K, V> {
  final V oldValue;

  ChangeRecordDelete(K key, this.oldValue) : super(key);
}

@immutable
class ChangeRecordUpdate<K, V> extends ChangeRecord<K, V> {
  final V oldValue, newValue;

  ChangeRecordUpdate(K key, this.oldValue, this.newValue) : super(key);
}
