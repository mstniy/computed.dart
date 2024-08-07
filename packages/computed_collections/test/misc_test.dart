import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/src/utils/option.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  test('option toString()', () {
    final some = Option.some(0);
    final none = Option.none();

    expect(some.toString(), 'Option.some(0)');
    expect(none.toString(), 'Option.none()');
  });

  group('KeyChanges', () {
    final changes = {0: ChangeRecordValue(1)}.lock;
    final x = KeyChanges(changes);
    test('hashCode', () {
      expect(x.hashCode, changes.hashCode);
    });
    test('toString()', () {
      expect(x.toString(), 'KeyChanges({0: ChangeRecordValue(1)})');
    });
  });

  group('ChangeEventReplace', () {
    final newCollection = {0: 1}.lock;
    final x = ChangeEventReplace(newCollection);
    test('hashCode', () {
      expect(x.hashCode, newCollection.hashCode);
    });
    test('toString()', () {
      expect(x.toString(), 'ChangeEventReplace({0: 1})');
    });
  });
}
