import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('snapshot works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    // Test both .remove on a fromChangeStream map as well as on another .remove on the same key
    for (var getM2 in [() => m1.remove(0), () => m1.remove(0).remove(0)]) {
      final m2 = getM2();
      IMap<int, int>? lastRes;
      final sub = m2.snapshot.listen((event) {
        lastRes = event;
      }, (e) => fail(e.toString()));
      await Future.value();
      expect(lastRes, {}.lock);
      s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
      expect(lastRes, {}.lock);
      s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
      expect(lastRes, {1: 2}.lock);
      s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
      expect(lastRes, {1: 2}.lock);
      s.add(KeyChanges({1: ChangeRecordValue(3)}.lock));
      expect(lastRes, {1: 3}.lock);
      s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
      expect(lastRes, {1: 3}.lock);
      s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
      expect(lastRes, {}.lock);
      s.add(ChangeEventReplace({0: 0, 4: 5}.lock));
      expect(lastRes, {4: 5}.lock);

      sub.cancel();

      // Clear m1 in preparation of the next iteration
      s.add(ChangeEventReplace(<int, int>{}.lock));
    }
  });

  test('remove on different key works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.remove(0).remove(1);

    IMap<int, int>? lastRes;
    final sub = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(lastRes, {}.lock);
    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(lastRes, {}.lock);
    s.add(KeyChanges({2: ChangeRecordValue(2)}.lock));
    expect(lastRes, {2: 2}.lock);
    s.add(KeyChanges({3: ChangeRecordValue(3)}.lock));
    expect(lastRes, {2: 2, 3: 3}.lock);

    sub.cancel();
  });

  test('operator[] and changes works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.remove(0);

    var callCnt1 = 0;
    int? lastRes1;
    final sub1 = m2[0].listen((event) {
      callCnt1++;
      lastRes1 = event;
    }, (e) => fail(e.toString()));

    var callCnt2 = 0;
    int? lastRes2;
    final sub2 = m2[1].listen((event) {
      callCnt2++;
      lastRes2 = event;
    }, (e) => fail(e.toString()));

    var callCnt3 = 0;
    ChangeEvent<int, int>? lastRes3;
    final sub3 = m2.changes.listen((c) {
      callCnt3++;
      lastRes3 = c;
    }, (e) => fail(e.toString()));

    await Future.value();
    await Future.value();
    expect(callCnt1, 1);
    expect(callCnt2, 1);
    expect(callCnt3, 0);
    expect(lastRes1, null);
    expect(lastRes2, null);

    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(callCnt2, 1);
    expect(callCnt3, 0);

    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    await Future.value();
    expect(callCnt2, 2);
    expect(lastRes2, 2);
    expect(callCnt3, 1);
    expect(lastRes3, KeyChanges({1: ChangeRecordValue(2)}.lock));
    s.add(KeyChanges({1: ChangeRecordValue(3)}.lock));
    await Future.value();
    expect(callCnt2, 3);
    expect(lastRes2, 3);
    expect(callCnt3, 2);
    expect(lastRes3, KeyChanges({1: ChangeRecordValue(3)}.lock));
    s.add(KeyChanges({0: ChangeRecordValue(4)}.lock));
    await Future.value();
    expect(callCnt2, 3);
    expect(callCnt3, 2);
    s.add(ChangeEventReplace({0: 2, 5: 6}.lock));
    await Future.value();
    expect(callCnt2, 4);
    expect(lastRes2, null);
    expect(callCnt3, 3);
    expect(lastRes3, ChangeEventReplace({5: 6}.lock));
    s.add(ChangeEventReplace({1: 1, 5: 6}.lock));
    await Future.value();
    expect(callCnt2, 5);
    expect(lastRes2, 1);
    expect(callCnt3, 4);
    expect(lastRes3, ChangeEventReplace({1: 1, 5: 6}.lock));

    expect(callCnt1, 1);

    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
  });

  test('attributes are coherent', () async {
    final m = IComputedMap({0: 1, 1: 2, 2: 3}.lock);
    final a = m.remove(0);
    final b = a.remove(1);
    final c = a.remove(3);
    await testCoherenceInt(a, {1: 2, 2: 3}.lock);
    await testCoherenceInt(b, {2: 3}.lock);
    await testCoherenceInt(c, {1: 2, 2: 3}.lock);
  });

  test('add on remove works', () async {
    final m = IComputedMap({0: 1, 1: 2, 2: 3}.lock);
    final a = m.remove(0);
    final b = a.add(0, 2);
    final c = a.add(1, 3);
    await testCoherenceInt(b, {0: 2, 1: 2, 2: 3}.lock);
    await testCoherenceInt(c, {1: 3, 2: 3}.lock);
  });
}
