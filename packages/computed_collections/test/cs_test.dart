import 'dart:async';

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
    final m = ComputedMap.fromChangeStream($(() => s.use));
    IMap<int, int>? lastRes;
    final sub = m.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(lastRes, {0: 1}.lock);
    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(lastRes, {0: 1, 1: 2}.lock);
    s.add(KeyChanges({1: ChangeRecordValue(3)}.lock));
    expect(lastRes, {0: 1, 1: 3}.lock);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes, {1: 3}.lock);
    s.add(ChangeEventReplace({4: 5}.lock));
    expect(lastRes, {4: 5}.lock);

    sub.cancel();
  });

  test('operator[] works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = ComputedMap.fromChangeStream($(() => s.use));

    var callCnt1 = 0;
    int? lastRes1;
    final sub1 = m[0].listen((event) {
      callCnt1++;
      lastRes1 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt1, 0);
    await Future.value();
    expect(callCnt1, 1);
    expect(lastRes1, null);

    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(callCnt1, 2);
    expect(lastRes1, 1);

    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(callCnt1, 2);
    s.add(KeyChanges({1: ChangeRecordValue(3)}.lock));
    expect(callCnt1, 2);
    s.add(KeyChanges({0: ChangeRecordValue(4)}.lock));
    expect(callCnt1, 3);
    expect(lastRes1, 4);

    var callCnt2 = 0;
    int? lastRes2;
    final sub2 = m[0].listen((event) {
      callCnt2++;
      lastRes2 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt2, 0);
    await Future.value();
    expect(callCnt2, 1);
    expect(lastRes2, 4);

    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(callCnt1, 4);
    expect(lastRes1, null);
    expect(callCnt2, 2);
    expect(lastRes2, null);
    s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(callCnt1, 4);
    expect(callCnt2, 2);
    s.add(ChangeEventReplace({4: 5}.lock));
    expect(callCnt1, 4);
    expect(callCnt2, 2);
    s.add(ChangeEventReplace({0: 0, 1: 1}.lock));
    expect(callCnt1, 5);
    expect(lastRes1, 0);
    expect(callCnt2, 3);
    expect(lastRes1, 0);

    int? lastRes3;
    var callCnt3 = 0;
    final sub3 = m[1].listen((event) {
      callCnt3++;
      lastRes3 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt3, 0);
    await Future.value();
    expect(callCnt3, 1);
    expect(lastRes3, 1);

    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    expect(callCnt1, 5);
    expect(callCnt2, 3);
    expect(callCnt3, 2);
    expect(lastRes3, 2);

    for (var i = 0; i < 5; i++) {
      await Future.value(); // No more updates
    }
    expect(callCnt1, 5);
    expect(callCnt2, 3);
    expect(callCnt3, 2);

    sub1.cancel();

    s.add(ChangeEventReplace({0: 1, 1: 3}.lock));
    for (var i = 0; i < 5; i++) {
      await Future.value();
    }
    expect(callCnt1, 5); // The listener has been cancelled
    expect(callCnt2, 4);
    expect(lastRes2, 1);
    expect(callCnt3, 3);
    expect(lastRes3, 3);

    sub3.cancel();
    sub2.cancel();

    s.add(ChangeEventReplace({0: 2, 1: 4}.lock));
    for (var i = 0; i < 5; i++) {
      await Future.value();
    }
    expect(callCnt1, 5);
    expect(callCnt2, 4);
    expect(callCnt3, 3);
  });

  test('propagates exceptions', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = ComputedMap.fromChangeStream($(() => s.use));
    await testExceptions(m, s);
  });

  test('propagates the change stream', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = ComputedMap.fromChangeStream($(() => s.use));
    ChangeEvent<int, int>? lastRes;
    var callCnt = 0;
    final sub = m.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(callCnt, 0);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(callCnt, 1);
    expect(lastRes, KeyChanges({0: ChangeRecordValue(1)}.lock));

    sub.cancel();
  });

  test('disposes of the old value upon cancellation', () async {
    final s = StreamController<ChangeEvent<int, int>>.broadcast(sync: true);
    final stream = s.stream;
    final m = ComputedMap.fromChangeStream($(() => stream.use));
    var lCnt = 0;
    int? lastRes;
    var sub = m[0].listen((event) {
      lCnt++;
      lastRes = event;
    }, null);
    await Future.value();
    expect(lCnt, 1);
    expect(lastRes, null);

    s.add(ChangeEventReplace({0: 1}.lock));
    expect(lCnt, 2);
    expect(lastRes, 1);

    sub.cancel();

    await testCoherenceInt(m, <int, int>{}.lock);
  });

  test('attributes are coherent', () async {
    final s = ValueStream<ChangeEvent<int, int>>.seeded(
        ChangeEventReplace({1: 2}.lock));
    final m = ComputedMap.fromChangeStream($(() => s.use));
    await testCoherenceInt(m, {1: 2}.lock);
  });
}
