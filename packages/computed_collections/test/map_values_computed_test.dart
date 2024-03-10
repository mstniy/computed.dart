import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  test('incremental update works', () async {
    for (var noValueSentinel in [null, 42]) {
      final s = ValueStream<ChangeEvent<int, int>>(sync: true);
      final s2 = ValueStream<int>.seeded(0, sync: true);
      final m1 = IComputedMap.fromChangeStream(s);
      final m2 =
          m1.mapValuesComputed((k, v) => $(() => v + s2.use), noValueSentinel);
      IMap<int, int?>? lastRes;
      final sub = m2.snapshot.listen((event) {
        lastRes = event;
      }, (e) => fail(e.toString()));
      await Future.value();
      expect(lastRes, {}.lock);
      s.add(KeyChanges({0: ChangeRecordInsert(1)}.lock));
      await Future.value();
      expect(lastRes, {0: noValueSentinel}.lock);
      await Future.value();
      expect(lastRes, {0: 1}.lock);
      s2.add(1);
      await Future.value();
      expect(lastRes, {0: 2}.lock);

      s.add(KeyChanges({0: ChangeRecordUpdate(2)}.lock));
      await Future.value();
      expect(lastRes, {0: noValueSentinel}.lock);
      await Future.value();
      expect(lastRes, {0: 3}.lock);
      s2.add(2);
      await Future.value();
      expect(lastRes, {0: 4}.lock);
      s.add(KeyChanges({1: ChangeRecordInsert(1)}.lock));
      await Future.value();
      expect(lastRes, {0: 4, 1: noValueSentinel}.lock);
      await Future.value();
      expect(lastRes, {0: 4, 1: 3}.lock);
      s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
      await Future.value();
      expect(lastRes, {1: 3}.lock);
      s2.add(3);
      s.add(ChangeEventReplace({4: 5}.lock));
      await Future.value();
      await Future.value();
      expect(lastRes, {4: noValueSentinel}.lock);
      await Future.value();
      expect(lastRes, {4: 8}.lock);

      sub.cancel();
    }
  });

  test('initial computation works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final s2 = ValueStream<int>.seeded(5, sync: true);
    s.add(ChangeEventReplace({0: 1, 2: 3}.lock));
    final m1 = IComputedMap.fromChangeStream(s);
    final sub1 = m1.snapshot.listen(null, null); // Force m1 to be computed
    await Future.value();

    final m2 = m1.mapValuesComputed((k, v) {
      return $(() => v + s2.use);
    }, null);
    IMap<int, int?>? lastRes;
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
    final m1 = IComputedMap.fromChangeStream(s);
    var cCnt = 0;
    final m2 = m1.mapValuesComputed(
        (k, v) => $(() {
              cCnt++;
              return v + s2.use;
            }),
        null);

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

    s.add(KeyChanges({0: ChangeRecordInsert(1)}.lock));
    await Future.value();
    expect(cCnt, 2);
    expect(callCnt1, 1);
    await Future.value();
    // Two runs in which it throws NVE, two runs after subscribing to [s2]
    expect(cCnt, 4);
    expect(callCnt1, 2);
    expect(lastRes1, 6);

    s2.add(0);
    expect(cCnt, 6);
    expect(callCnt1, 3);
    expect(lastRes1, 1);

    sub1.cancel();

    s2.add(1);
    expect(cCnt, 8);
    expect(callCnt1, 3);

    sub2.cancel();
    s2.add(2);
    expect(cCnt, 8);
    expect(callCnt1, 3);
  });

  // TODO: Test a non-null sentinel value

  test('propagates the change stream', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final s2 = ValueStream<int>.seeded(5, sync: true);
    final m1 = IComputedMap.fromChangeStream(s);
    final m2 =
        m1.mapValuesComputed((key, value) => $(() => value + s2.use), null);
    ChangeEvent<int, int?>? lastRes;
    var callCnt = 0;
    final sub = m2.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(callCnt, 0);
    s.add(KeyChanges({0: ChangeRecordInsert(1)}.lock));
    await Future.value();
    expect(callCnt, 1);
    expect(lastRes, KeyChanges({0: ChangeRecordInsert(null)}.lock));
    await Future.value();
    expect(callCnt, 2);
    expect(lastRes, KeyChanges({0: ChangeRecordUpdate(6)}.lock));

    s.add(KeyChanges({1: ChangeRecordInsert(2)}.lock));
    await Future.value();
    expect(callCnt, 3);
    expect(lastRes, KeyChanges({1: ChangeRecordInsert(null)}.lock));
    await Future.value();
    expect(callCnt, 4);
    expect(lastRes, KeyChanges({1: ChangeRecordUpdate(7)}.lock));

    s.add(KeyChanges({0: ChangeRecordUpdate(2)}.lock));
    await Future.value();
    expect(callCnt, 5);
    expect(lastRes, KeyChanges({0: ChangeRecordUpdate(null)}.lock));
    await Future.value();
    expect(callCnt, 6);
    expect(lastRes, KeyChanges({0: ChangeRecordUpdate(7)}.lock));

    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(callCnt, 7);
    expect(lastRes, KeyChanges({0: ChangeRecordDelete()}.lock));

    s.add(ChangeEventReplace({0: 5, 1: 6, 2: 7}.lock));
    await Future.value();
    expect(callCnt, 8);
    expect(lastRes, ChangeEventReplace({0: null, 1: null, 2: null}.lock));
    await Future.value();
    expect(callCnt, 9);
    expect(lastRes, KeyChanges({0: ChangeRecordUpdate(10)}.lock));
    await Future.value();
    expect(callCnt, 10);
    expect(lastRes, KeyChanges({1: ChangeRecordUpdate(11)}.lock));
    await Future.value();
    expect(callCnt, 11);
    expect(lastRes, KeyChanges({2: ChangeRecordUpdate(12)}.lock));

    await Future.value(); // No more calls
    expect(callCnt, 11);

    sub.cancel();
  });
}