import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/src/utils/merging_change_stream.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

// This file only has tests for behaviour which cannot be tested otherwise,
// as a coincidental result of the implementation of the operators.
void main() {
  test('works', () async {
    final s = MergingChangeStream<int, int>();

    var cnt = 0;
    ChangeEvent<int, int>? last;

    final sub = s.listen((event) {
      cnt++;
      last = event;
    });

    s.add(ChangeEventReplace(<int, int>{0: 1, 2: 3}.lock));
    s.add(KeyChanges(
        {0: ChangeRecordDelete<int>(), 2: ChangeRecordDelete<int>()}.lock));
    expect(cnt, 0);

    await Future.value();
    expect(cnt, 1);
    expect(last, ChangeEventReplace(<int, int>{}.lock));

    sub.cancel();
  });
}
