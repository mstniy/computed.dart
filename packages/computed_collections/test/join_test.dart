import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('attributes are coherent', () async {
    final x = ComputedMap.fromIMap({0: 1, 1: 2}.lock)
        .join(ComputedMap.fromIMap({1: 3, 2: 4, 3: 5}.lock));
    await testCoherence(x, {1: (2, 3)}.lock, 0, (0, 1));

    final y = ComputedMap.fromIMap({0: 1, 1: 2, 2: 3}.lock)
        .join(ComputedMap.fromIMap({0: 0}.lock));
    await testCoherence(y, {0: (1, 0)}.lock, 1, (0, 1));
  });

  test('propagates the change stream', () async {
    final s = StreamController<
        (ChangeEvent<int, int>, ChangeEvent<int, int>)>.broadcast(sync: true);
    final s2 = s.stream;
    final x = ComputedMap.fromChangeStream($(() => s2.use.$1));
    final y = ComputedMap.fromChangeStream($(() => s2.use.$2));
    final z = x.join(y);

    ChangeEvent<int, (int, int)>? lastRes;
    var callCnt = 0;
    final sub = z.changes.listen((event) {
      callCnt++;
      lastRes = event;
    });

    for (var i = 0; i < 5; i++) await Future.value();
    expect(callCnt, 0);

    s.add((
      KeyChanges({0: ChangeRecordValue(1), 1: ChangeRecordValue(2)}.lock),
      KeyChanges({1: ChangeRecordValue(3), 2: ChangeRecordValue(4)}.lock)
    ));
    expect(callCnt, 1);
    expect(lastRes, KeyChanges({1: ChangeRecordValue((2, 3))}.lock));

    s.add((
      KeyChanges(
          {0: ChangeRecordDelete<int>(), 1: ChangeRecordDelete<int>()}.lock),
      KeyChanges(
          {1: ChangeRecordDelete<int>(), 2: ChangeRecordDelete<int>()}.lock)
    ));
    expect(callCnt, 2);
    // join is pretty liberal when it comes to broadcasting deletions
    // this is technically still correct, though
    expect(
        lastRes,
        KeyChanges({
          0: ChangeRecordDelete<int>(),
          1: ChangeRecordDelete<int>(),
          2: ChangeRecordDelete<int>()
        }.lock));

    s.add((
      ChangeEventReplace({0: 1, 1: 2, 2: 3}.lock),
      KeyChanges({1: ChangeRecordDelete<int>(), 2: ChangeRecordDelete<int>()}
          .lock) // Same as last one
    ));
    expect(callCnt, 3);
    expect(lastRes, ChangeEventReplace({}.lock));

    s.add((
      ChangeEventReplace({0: 1, 1: 2, 2: 3}.lock), // Same as last one
      ChangeEventReplace({1: 1, 2: 2}.lock)
    ));
    expect(callCnt, 4);
    expect(lastRes, ChangeEventReplace({1: (2, 1), 2: (3, 2)}.lock));

    s.add((
      ChangeEventReplace({0: 1, 1: 2, 2: 3}.lock), // Same as last one
      KeyChanges(// Note that the deletion on 3 is redundant
          {1: ChangeRecordDelete<int>(), 3: ChangeRecordDelete<int>()}.lock)
    ));
    expect(callCnt, 5);
    expect(lastRes,
        KeyChanges({1: ChangeRecordDelete(), 3: ChangeRecordDelete()}.lock));

    sub.cancel();
  });
}
