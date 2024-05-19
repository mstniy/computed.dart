import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  test('incremental update works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final s2 = ValueStream<int>.seeded(0, sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.mapValuesComputed((k, v) => $(() => v + s2.use));
    IMap<int, int?>? lastRes;
    final sub = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(lastRes, {}.lock);
    await Future.value();
    await Future.value();
    expect(lastRes, {0: 1}.lock);
    s2.add(1);
    await Future.value();
    expect(lastRes, {0: 2}.lock);

    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    await Future.value();
    await Future.value();
    expect(lastRes, {0: 3}.lock);
    s2.add(2);
    await Future.value();
    expect(lastRes, {0: 4}.lock);
    s.add(KeyChanges({1: ChangeRecordValue(1)}.lock));
    await Future.value();
    await Future.value();
    expect(lastRes, {0: 4, 1: 3}.lock);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(lastRes, {1: 3}.lock);
    s2.add(3);
    s.add(ChangeEventReplace({4: 5}.lock));
    await Future.value();
    expect(lastRes, {}.lock);
    await Future.value();
    expect(lastRes, {4: 8}.lock);

    sub.cancel();
  });

  test('initial computation works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final s2 = ValueStream<int>.seeded(5, sync: true);
    s.add(ChangeEventReplace({0: 1, 2: 3}.lock));
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final sub1 = m1.snapshot.listen(null, null); // Force m1 to be computed
    await Future.value();

    final m2 = m1.mapValuesComputed((k, v) => $(() => v + s2.use));
    IMap<int, int>? lastRes;
    final sub2 = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {0: 6, 2: 8}.lock);

    sub1.cancel();
    sub2.cancel();
  });
  test('operator[] works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final s2 = ValueStream<int>.seeded(5, sync: true);
    final s3 = ValueStream<int>(sync: true);
    var useS2 = true;
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    var cCnt = 0;
    final m2 = m1.mapValuesComputed((k, v) => $(() {
          cCnt++;
          return v + (useS2 ? s2.use : s3.use);
        }));

    var callCnt1 = 0;
    int? lastRes1;
    final sub1 = m2[0].listen((event) {
      callCnt1++;
      lastRes1 = event;
    }, (e) => fail(e.toString()));

    final sub2 = m2[0].listen(null, null);

    await Future.value();
    expect(cCnt, 0);
    expect(callCnt1, 1);
    expect(lastRes1, null);

    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(cCnt, 2);
    expect(callCnt1, 1);
    expect(lastRes1, null);
    await Future.value();
    // Two runs in which it throws NVE, two runs after subscribing to [s2]
    expect(cCnt, 4);
    expect(callCnt1, 2);
    expect(lastRes1, 6);

    useS2 = false; // Note that s3 has no value at this point
    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    await Future.value();
    expect(cCnt, 6);
    expect(callCnt1, 3);
    expect(lastRes1, null);

    s3.add(0);
    expect(cCnt, 8);
    expect(callCnt1, 4);
    expect(lastRes1, 2);

    sub1.cancel();

    s3.add(1);
    expect(cCnt, 10);
    expect(callCnt1, 4);

    sub2.cancel();
    s3.add(2);
    expect(cCnt, 10);
    expect(callCnt1, 4);
  });

  test('propagates the change stream', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final s2 = ValueStream<int>.seeded(5, sync: true);
    final s3 = ValueStream<int>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    var useS2 = true;
    final m2 = m1.mapValuesComputed(
        (key, value) => $(() => value + (useS2 ? s2.use : s3.use)));
    ChangeEvent<int, int?>? lastRes;
    var callCnt = 0;
    final sub = m2.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(callCnt, 0);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(callCnt, 0);
    await Future.value();
    expect(callCnt, 1);
    expect(lastRes, KeyChanges({0: ChangeRecordValue(6)}.lock));

    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(callCnt, 1);
    await Future.value();
    expect(callCnt, 2);
    expect(lastRes, KeyChanges({1: ChangeRecordValue(7)}.lock));

    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(callCnt, 2);
    await Future.value();
    expect(callCnt, 3);
    expect(lastRes, KeyChanges({0: ChangeRecordValue(7)}.lock));

    useS2 = false;
    s.add(KeyChanges({0: ChangeRecordValue(3)}.lock));
    expect(callCnt, 3);
    await Future.value();
    expect(callCnt, 4);
    expect(lastRes,
        KeyChanges({0: ChangeRecordDelete()}.lock)); // s3 has no value yet
    s.add(KeyChanges({0: ChangeRecordValue(4)}.lock));
    await Future.value();
    expect(callCnt, 4); // Not notified, as the last event was already deletion
    expect(lastRes, KeyChanges({0: ChangeRecordDelete()}.lock));
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(callCnt, 4);
    s.add(KeyChanges({0: ChangeRecordValue(4)}.lock));
    await Future.value();
    expect(callCnt, 4); // Not notified, as s3 still has no value
    s3.add(0);
    expect(callCnt, 4); // Waits for the microtask to end to publish new state
    await Future.value();
    expect(callCnt, 5);
    expect(lastRes, KeyChanges({0: ChangeRecordValue(4)}.lock));
    useS2 = true;

    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 5);
    await Future.value();
    expect(callCnt, 6);
    expect(lastRes, KeyChanges({0: ChangeRecordDelete()}.lock));

    s.add(ChangeEventReplace({0: 5, 1: 6, 2: 7}.lock));
    expect(callCnt, 6);
    await Future.value();
    expect(callCnt, 7);
    expect(lastRes, ChangeEventReplace({0: 10, 1: 11, 2: 12}.lock));

    s2.add(6);
    expect(callCnt, 7);
    await Future.value();
    expect(callCnt, 8);
    expect(
        lastRes,
        KeyChanges({
          0: ChangeRecordValue(11),
          1: ChangeRecordValue(12),
          2: ChangeRecordValue(13)
        }.lock));

    s.add(ChangeEventReplace({0: 8, 1: 9, 2: 10}.lock));
    s.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    s2.add(7);
    s.add(KeyChanges({3: ChangeRecordValue(11)}.lock));
    expect(callCnt, 8);
    await Future.value();
    expect(callCnt, 9);
    expect(lastRes, ChangeEventReplace({2: 17, 0: 7}.lock));
    await Future.value();
    expect(callCnt, 10);
    expect(lastRes, KeyChanges({3: ChangeRecordValue(18)}.lock));

    await Future.value(); // No more calls
    expect(callCnt, 10);

    sub.cancel();
  });

  test('operator[] and containsKey opportunistically use the snapshot',
      () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = IComputedMap.fromChangeStream($(() => s.use));

    var cCnt = 0;

    final m2 = m.mapValuesComputed((key, value) => $(() {
          cCnt++;
          return value;
        }));

    final sub1 = m2.snapshot.listen(null, null);

    List<int?> resCache2 = [];
    final sub2 = m2[0].listen((e) {
      resCache2.add(e);
    }, null);

    List<bool> resCache3 = [];
    final sub3 = m2.containsKey(0).listen((e) {
      resCache3.add(e);
    }, null);

    s.add(ChangeEventReplace({0: 1}.lock));
    await Future.value();
    expect(cCnt, 2); // And not 4 or 6
    expect(resCache2, [null, 1]);
    expect(resCache3, [false, true]);

    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
  });

  test('operator[] and containsKey are key-local', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = IComputedMap.fromChangeStream($(() => s.use));

    var cCnt = 0;

    final m2 = m.mapValuesComputed((key, value) => $(() {
          expect(key, 0);
          cCnt++;
          return value;
        }));

    List<int?> resCache1 = [];
    final sub1 = m2[0].listen((e) {
      resCache1.add(e);
    }, null);

    List<bool> resCache2 = [];
    final sub2 = m2.containsKey(0).listen((e) {
      resCache2.add(e);
    }, null);

    s.add(ChangeEventReplace({0: 1, 1: 2}.lock));
    await Future.value();
    expect(cCnt, 2);
    expect(resCache1, [1]);
    expect(resCache2, [true]);

    sub1.cancel();
    sub2.cancel();
  });
}
