import 'package:computed_collections/change_event.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  group('ChangeRecord', () {
    test('operator== works', () async {
      expect(ChangeRecordInsert<int>(0), ChangeRecordInsert<int>(0));
      expect(ChangeRecordInsert<int>(0), isNot(ChangeRecordInsert<int>(1)));

      expect(ChangeRecordUpdate<int>(0), ChangeRecordUpdate<int>(0));
      expect(ChangeRecordUpdate<int>(0), isNot(ChangeRecordUpdate<int>(1)));

      expect(ChangeRecordDelete<int>(), ChangeRecordDelete<int>());
      expect(ChangeRecordDelete<int>(), isNot(ChangeRecordDelete<String>()));

      expect(ChangeEventReplace<int, int>({0: 1}.lock),
          ChangeEventReplace<int, int>({0: 1}.lock));
      expect(ChangeEventReplace<int, int>({0: 1}.lock),
          isNot(ChangeEventReplace<int, int>({0: 2}.lock)));
    });
  });
}
