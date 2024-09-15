import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('snapshot works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    // Test both .add on a fromChangeStream map as well as on an added map
    for (var getM2 in [() => m1.add(0, 1), () => m1.add(0, 2).add(0, 1)]) {
      final m2 = getM2();
      IMap<int, int>? lastRes;
      final sub = m2.snapshot.listen((event) {
        lastRes = event;
      }, (e) => fail(e.toString()));
      await Future.value();
      expect(lastRes, {0: 1}.lock);
      s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
      expect(lastRes, {0: 1}.lock);
      s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
      expect(lastRes, {0: 1}.lock);
      s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
      expect(lastRes, {0: 1, 1: 2}.lock);
      s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
      expect(lastRes, {0: 1, 1: 2}.lock);
      s.add(ChangeEventReplace({4: 5}.lock));
      expect(lastRes, {0: 1, 4: 5}.lock);

      sub.cancel();

      // Clear m1 in preparation of the next iteration
      s.add(ChangeEventReplace(<int, int>{}.lock));
    }
  });

  test('add on different key works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.add(0, 1).add(2, 3);

    IMap<int, int>? lastRes;
    final sub = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {0: 1, 2: 3}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(lastRes, {0: 1, 2: 3}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(lastRes, {0: 1, 2: 3}.lock);
    s.add(KeyChanges({4: ChangeRecordValue(5)}.lock));
    expect(lastRes, {0: 1, 2: 3, 4: 5}.lock);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes, {0: 1, 2: 3, 4: 5}.lock);
    s.add(ChangeEventReplace({6: 7}.lock));
    expect(lastRes, {0: 1, 2: 3, 6: 7}.lock);

    sub.cancel();
  });

  test('remove works', () async {
    final m1 = ComputedMap.fromIMap({0: 1}.lock).add(1, 2);
    final m2 = m1.remove(1);
    final m3 = m1.remove(0);

    await testCoherenceInt(m2, {0: 1}.lock);
    await testCoherenceInt(m3, {1: 2}.lock);
  });

  test('operator[] works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.add(0, 1);

    var callCnt1 = 0;
    int? lastRes1;
    final sub1 = m2[0].listen((event) {
      callCnt1++;
      lastRes1 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt1, 0);
    await Future.value();
    expect(callCnt1, 1);
    expect(lastRes1, 1);

    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(callCnt1, 1);

    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(callCnt1, 1);
    s.add(KeyChanges({1: ChangeRecordValue(3)}.lock));
    expect(callCnt1, 1);
    s.add(KeyChanges({0: ChangeRecordValue(4)}.lock));
    expect(callCnt1, 1);
    s.add(ChangeEventReplace({5: 6}.lock));
    expect(callCnt1, 1);

    var callCnt2 = 0;
    int? lastRes2;
    final sub2 = m2[1].listen((event) {
      callCnt2++;
      lastRes2 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt2, 0);
    await Future.value();
    expect(callCnt2, 1);
    expect(lastRes2, null);

    s.add(KeyChanges({5: ChangeRecordDelete<int>()}.lock));
    expect(callCnt1, 1);
    expect(callCnt2, 1);
    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(callCnt1, 1);
    expect(callCnt2, 2);
    expect(lastRes2, 2);
    s.add(KeyChanges({1: ChangeRecordValue(3)}.lock));
    expect(callCnt1, 1);
    expect(callCnt2, 3);
    expect(lastRes2, 3);
    s.add(ChangeEventReplace({1: 4}.lock));
    expect(callCnt1, 1);
    expect(callCnt2, 4);
    expect(lastRes2, 4);

    sub1.cancel();
    sub2.cancel();

    s.add(ChangeEventReplace({0: 3, 1: 5}.lock));
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callCnt1, 1); // The listeners have been cancelled
    expect(callCnt2, 4);
  });

  test('propagates the change stream', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.add(0, 1);
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
    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(callCnt, 1);
    expect(lastRes, KeyChanges({1: ChangeRecordValue(2)}.lock));
    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(callCnt, 1);
    s.add(KeyChanges({1: ChangeRecordValue(3)}.lock));
    expect(callCnt, 2);
    expect(lastRes, KeyChanges({1: ChangeRecordValue(3)}.lock));
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 2);
    s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 3);
    expect(lastRes, KeyChanges({1: ChangeRecordDelete()}.lock));
    s.add(ChangeEventReplace({0: 5, 1: 6, 2: 7}.lock));
    expect(callCnt, 4);
    expect(lastRes, ChangeEventReplace({0: 1, 1: 6, 2: 7}.lock));

    sub.cancel();
  });

  test('attributes are coherent', () async {
    final m = ComputedMap.fromIMap({0: 1}.lock);
    final a = m.add(1, 2);
    final b = a.add(0, 2);
    final c = a.add(0, 3);
    await testCoherenceInt(a, {0: 1, 1: 2}.lock);
    await testCoherenceInt(b, {0: 2, 1: 2}.lock);
    await testCoherenceInt(c, {0: 3, 1: 2}.lock);
  });
}
