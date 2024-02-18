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
}

@immutable
class ChangeRecordDelete<K, V> extends ChangeRecord<K, V> {
  final K key;
  final V oldValue;

  ChangeRecordDelete(this.key, this.oldValue);
}

@immutable
class ChangeRecordUpdate<K, V> extends ChangeRecord<K, V> {
  final K key;
  final V oldValue, newValue;

  ChangeRecordUpdate(this.key, this.oldValue, this.newValue);
}

@immutable
class ChangeRecordReplace<K, V> extends ChangeRecord<K, V> {
  final IMap<K, V> newCollection;

  ChangeRecordReplace(this.newCollection);
}
