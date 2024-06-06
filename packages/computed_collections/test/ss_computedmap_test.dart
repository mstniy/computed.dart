import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/src/ss_computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('works', () async {
    final ss = SnapshotStreamComputedMap($(() => {0: 1}.lock));
    await testCoherence(ss, {0: 1}.lock);
  });

  test('change stream works', () async {
    final ss = StreamController<IMap<int, int>>.broadcast(sync: true);
    final sstream = ss.stream;
    final m = SnapshotStreamComputedMap($(() => sstream.use));
    expect(
        await getValuesWhile(m.changes, () {
          ss.add({0: 1}.lock);
          ss.add({0: 1, 1: 2}.lock);
          ss.add({1: 3}.lock);
          ss.add({2: 4}.lock);
          ss.add(<int, int>{}.lock);
        }),
        [
          ChangeEventReplace({0: 1}.lock),
          KeyChanges({1: ChangeRecordValue(2)}.lock),
          KeyChanges(
              {0: ChangeRecordDelete<int>(), 1: ChangeRecordValue(3)}.lock),
          KeyChanges(
              {1: ChangeRecordDelete<int>(), 2: ChangeRecordValue(4)}.lock),
          KeyChanges({2: ChangeRecordDelete<int>()}.lock),
        ]);
  });
}
