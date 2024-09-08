import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('initial computation works', () async {
    final x = ComputedMap({0: 1, 1: 2}.lock);
    final y = x.addAll({1: 3, 2: 4}.lock);
    expect(await getValue(y.snapshot), {0: 1, 1: 3, 2: 4}.lock);
  });

  test('containsKey works', () async {
    final x = ComputedMap({0: 1, 1: 2}.lock);
    final y = x.addAll({1: 3, 2: 4}.lock);
    expect(await getValue(y.containsKey(0)), true);
    expect(await getValue(y.containsKey(1)), true);
    expect(await getValue(y.containsKey(2)), true);
    expect(await getValue(y.containsKey(3)), false);
  });

  test('containsValue works', () async {
    final x = ComputedMap({0: 1, 1: 4}.lock);
    final y = x.addAll({1: 3, 2: 4}.lock);
    expect(await getValue(y.containsValue(1)), true);
    expect(await getValue(y.containsValue(3)), true);
    expect(await getValue(y.containsValue(4)), true);
    expect(await getValue(y.containsValue(5)), false);
  });

  test('operator[] works', () async {
    final x = ComputedMap({0: 1, 1: 2}.lock);
    final y = x.addAll({1: 3, 2: 4}.lock);
    expect(await getValue(y[0]), 1);
    expect(await getValue(y[1]), 3);
    expect(await getValue(y[2]), 4);
    expect(await getValue(y[3]), null);
  });

  test('propagates the change stream', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.addAll({0: 1, 1: 2}.lock);
    ChangeEvent<int, int>? lastRes;
    var callCnt = 0;
    final sub = m2.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(callCnt, 0);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(callCnt, 0);
    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(callCnt, 0);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 0);
    s.add(KeyChanges({2: ChangeRecordValue(2)}.lock));
    expect(callCnt, 1);
    expect(lastRes, KeyChanges({2: ChangeRecordValue(2)}.lock));
    s.add(KeyChanges({2: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 2);
    expect(lastRes, KeyChanges({2: ChangeRecordDelete<int>()}.lock));
    s.add(ChangeEventReplace({0: 5, 2: 7}.lock));
    expect(callCnt, 3);
    expect(lastRes, ChangeEventReplace({0: 1, 1: 2, 2: 7}.lock));

    sub.cancel();
  });

  test('attributes are coherent', () async {
    final x = ComputedMap({0: 1, 1: 2}.lock);
    final y = x.addAll({1: 3, 2: 4}.lock);
    await testCoherenceInt(y, {0: 1, 1: 3, 2: 4}.lock);
  });
}
