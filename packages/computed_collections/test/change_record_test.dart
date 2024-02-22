import 'package:computed_collections/change_record.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  group('ChangeRecord', () {
    test('operator== works', () async {
      expect(ChangeRecordInsert<int, int>(0, 1),
          ChangeRecordInsert<int, int>(0, 1));
      expect(ChangeRecordInsert<int, int>(0, 1),
          isNot(ChangeRecordInsert<int, int>(0, 2)));
      expect(ChangeRecordInsert<int, int>(0, 1),
          isNot(ChangeRecordInsert<int, int>(1, 1)));

      expect(ChangeRecordUpdate<int, int>(0, 1, 2),
          ChangeRecordUpdate<int, int>(0, 1, 2));
      expect(ChangeRecordUpdate<int, int>(0, 1, 2),
          isNot(ChangeRecordUpdate<int, int>(0, 1, 3)));
      expect(ChangeRecordUpdate<int, int>(0, 1, 2),
          isNot(ChangeRecordUpdate<int, int>(0, 2, 2)));
      expect(ChangeRecordUpdate<int, int>(0, 1, 2),
          isNot(ChangeRecordUpdate<int, int>(1, 1, 2)));

      expect(ChangeRecordDelete<int, int>(0, 1),
          ChangeRecordDelete<int, int>(0, 1));
      expect(ChangeRecordDelete<int, int>(0, 1),
          isNot(ChangeRecordDelete<int, int>(0, 2)));
      expect(ChangeRecordDelete<int, int>(0, 1),
          isNot(ChangeRecordDelete<int, int>(1, 1)));

      expect(ChangeRecordReplace<int, int>({0: 1}.lock),
          ChangeRecordReplace<int, int>({0: 1}.lock));
      expect(ChangeRecordReplace<int, int>({0: 1}.lock),
          isNot(ChangeRecordReplace<int, int>({0: 2}.lock)));
    });
  });
}
