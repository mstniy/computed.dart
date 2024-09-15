import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('incremental update works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.mapValues((k, v) => v + 1);
    IMap<int, int>? lastRes;
    final sub = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(lastRes, {0: 2}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(lastRes, {0: 3}.lock);
    s.add(KeyChanges({1: ChangeRecordValue(1)}.lock));
    expect(lastRes, {0: 3, 1: 2}.lock);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes, {1: 2}.lock);
    s.add(ChangeEventReplace({4: 5}.lock));
    expect(lastRes, {4: 6}.lock);

    sub.cancel();
  });

  test('initial computation works', () async {
    final m1 = ComputedMap.fromIMap({0: 1, 2: 3}.lock);

    final m2 = m1.mapValues((k, v) {
      return v + 1;
    });

    expect(await getValue(m2.snapshot), {0: 2, 2: 4}.lock);
  });
  test('operator[] works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    var cCnt = 0;
    final m2 = m1.mapValues((k, v) {
      cCnt++;
      return v + 1;
    });

    var callCnt1 = 0;
    int? lastRes1;
    final sub1 = m2[0].listen((event) {
      callCnt1++;
      lastRes1 = event;
    }, (e) => fail(e.toString()));

    var callCnt2 = 0;
    int? lastRes2;
    final sub2 = m2[0].listen((event) {
      callCnt2++;
      lastRes2 = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(cCnt, 0);
    expect(callCnt1, 1);
    expect(lastRes1, null);
    expect(callCnt2, 1);
    expect(lastRes2, null);

    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(cCnt, 1);
    expect(callCnt1, 2);
    expect(lastRes1, 2);
    expect(callCnt2, 2);
    expect(lastRes2, 2);

    sub1.cancel();
    sub2.cancel();
  });

  test('propagates the change stream', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.mapValues((key, value) => value + 1);
    ChangeEvent<int, int>? lastRes;
    var callCnt = 0;
    final sub = m2.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(callCnt, 0);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(callCnt, 1);
    expect(lastRes, KeyChanges({0: ChangeRecordValue(2)}.lock));

    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(callCnt, 2);
    expect(lastRes, KeyChanges({1: ChangeRecordValue(3)}.lock));

    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(callCnt, 3);
    expect(lastRes, KeyChanges({0: ChangeRecordValue(3)}.lock));

    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 4);
    expect(lastRes, KeyChanges({0: ChangeRecordDelete()}.lock));

    s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 5);
    expect(lastRes, KeyChanges({1: ChangeRecordDelete()}.lock));
    s.add(ChangeEventReplace({0: 5, 1: 6, 2: 7}.lock));
    expect(callCnt, 6);
    expect(lastRes, ChangeEventReplace({0: 6, 1: 7, 2: 8}.lock));

    sub.cancel();
  });

  test('operator[] opportunistically uses the snapshot', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = ComputedMap.fromChangeStream($(() => s.use));

    var cCnt = 0;

    final m2 = m.mapValues((key, value) {
      cCnt++;
      return value + 1;
    });

    final sub1 = m2.snapshot.listen(null, null);

    List<int?> resCache2 = [];
    final sub2 = m2[0].listen((e) {
      resCache2.add(e);
    }, null);

    s.add(ChangeEventReplace({0: 1}.lock));
    expect(cCnt, 1); // And not 2 or 3
    expect(resCache2, [2]);
    for (var i = 0; i < 5; i++) {
      await Future.value();
    }
    expect(cCnt, 1); // Still
    expect(resCache2, [2]);

    sub1.cancel();
    sub2.cancel();
  });

  test('attributes are coherent', () async {
    final m = ComputedMap.fromIMap({0: 1}.lock);
    final mv = m.mapValues((key, value) => value + 1);
    await testCoherenceInt(mv, {0: 2}.lock);
  });
}
