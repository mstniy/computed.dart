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
    final m2 = m1.removeWhere((k, v) => (v % 2) == 0);
    IMap<int, int>? lastRes;
    final sub = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(lastRes, {0: 1}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(lastRes, {}.lock);
    s.add(KeyChanges({1: ChangeRecordValue(1)}.lock));
    expect(lastRes, {1: 1}.lock);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes, {1: 1}.lock);
    s.add(ChangeEventReplace({4: 5, 5: 6, 6: 7}.lock));
    expect(lastRes, {4: 5, 6: 7}.lock);

    sub.cancel();
  });

  test('initial computation works', () async {
    final m1 = ComputedMap({0: 1, 1: 1, 2: 3, 3: 3}.lock);

    final m2 = m1.removeWhere((k, v) {
      return k == v;
    });

    expect(await getValue(m2.snapshot), {0: 1, 2: 3}.lock);
  });
  test('operator[] works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    var cCnt = 0;
    final m2 = m1.removeWhere((k, v) {
      cCnt++;
      return k == v;
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

    var callCnt3 = 0;
    int? lastRes3;
    final sub3 = m2[1].listen((event) {
      callCnt3++;
      lastRes3 = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(cCnt, 0);
    expect(callCnt1, 1);
    expect(lastRes1, null);
    expect(callCnt2, 1);
    expect(lastRes2, null);
    expect(callCnt3, 1);
    expect(lastRes3, null);

    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(cCnt, 2);
    expect(callCnt1, 2);
    expect(lastRes1, 1);
    expect(callCnt2, 2);
    expect(lastRes2, 1);
    expect(callCnt3, 1);

    s.add(KeyChanges({1: ChangeRecordValue(1)}.lock));
    expect(cCnt, 4);
    expect(callCnt1, 2);
    expect(callCnt2, 2);
    expect(callCnt3, 1);

    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(cCnt, 6);
    expect(callCnt1, 3);
    expect(lastRes1, 2);
    expect(callCnt2, 3);
    expect(lastRes2, 2);
    expect(callCnt3, 1);

    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
  });

  test('propagates the change stream', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.removeWhere((key, value) => key == value);
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
    expect(lastRes, KeyChanges({0: ChangeRecordValue(1)}.lock));

    s.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    expect(callCnt, 2);
    expect(lastRes, KeyChanges({0: ChangeRecordDelete<int>()}.lock));

    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(callCnt, 3);
    expect(lastRes, KeyChanges({1: ChangeRecordValue(2)}.lock));

    s.add(KeyChanges({1: ChangeRecordValue(1)}.lock));
    expect(callCnt, 4);
    expect(lastRes, KeyChanges({1: ChangeRecordDelete<int>()}.lock));

    s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 4);

    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 5);
    // Note that this is a redundant deletion
    expect(lastRes, KeyChanges({0: ChangeRecordDelete<int>()}.lock));

    s.add(ChangeEventReplace({0: 0, 1: 1, 2: 3}.lock));
    expect(callCnt, 6);
    expect(lastRes, ChangeEventReplace({2: 3}.lock));

    sub.cancel();
  });

  test('operator[] and containsKey opportunistically uses the snapshot',
      () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = ComputedMap.fromChangeStream($(() => s.use));

    var cCnt = 0;

    final m2 = m.removeWhere((key, value) {
      cCnt++;
      return key == value;
    });

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
    expect(resCache2, [1]);
    expect(resCache3, [true]);

    sub1.cancel();
    // Computed scheduled a microtask to re-run the operator[]/containsKey shared computation,
    // now that the snapshot it useWeak-d has no listener.
    await Future.value(); // The microtask runs
    // The shared computation tries to access the parent, which has since lost its state as it has lost
    // all listeners. Eventually leading Computed to re-subcribe to [s].
    expect(cCnt, 2);
    expect(resCache2, [1, null]);
    expect(resCache3, [true, false]);
    await Future.value(); // [s] notifies Computed
    // [m]'s CSTracker pushes to the key stream
    // The shared computation runs on a meaningful parent.containsKey/operator[],
    // and in return calls the user filter.
    expect(cCnt, 4);
    expect(resCache2, [1, null, 1]);
    expect(resCache3, [true, false, true]);

    // Also test that operator[] and containsKey share the underlying filter computation
    s.add(ChangeEventReplace({0: 0}.lock));
    expect(cCnt, 6); // And not 8
    expect(resCache2, [1, null, 1, null]);
    expect(resCache3, [true, false, true, false]);

    sub2.cancel();
    sub3.cancel();
  });

  test('attributes are coherent', () async {
    final m = ComputedMap({0: 1, 1: 1}.lock);
    final mv = m.removeWhere((key, value) => key == value);
    await testCoherenceInt(mv, {0: 1}.lock);
  });
}
