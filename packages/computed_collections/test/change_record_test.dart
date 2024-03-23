import 'package:computed_collections/change_event.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  group('ChangeRecord', () {
    test('operator== works', () async {
      expect(ChangeRecordValue<int>(0), ChangeRecordValue<int>(0));
      expect(ChangeRecordValue<int>(0), ChangeRecordValue<int?>(0));
      expect(ChangeRecordValue<int>(0), isNot(ChangeRecordValue<int>(1)));

      expect(ChangeRecordDelete<int>(), ChangeRecordDelete<int>());
      expect(ChangeRecordDelete<int>(), ChangeRecordDelete<int?>());
      expect(ChangeRecordDelete<int>(), ChangeRecordDelete<String>());
      expect(ChangeRecordDelete<int>(), isNot(ChangeRecordValue<int>(0)));

      expect(ChangeEventReplace<int, int>({0: 1}.lock),
          ChangeEventReplace<int, int>({0: 1}.lock));
      expect(ChangeEventReplace<int, int>({0: 1}.lock),
          ChangeEventReplace<int?, int?>({0: 1}.lock));
      expect(ChangeEventReplace<int, int>({0: 1}.lock),
          isNot(ChangeEventReplace<int, int>({0: 2}.lock)));
    });
  });
}
