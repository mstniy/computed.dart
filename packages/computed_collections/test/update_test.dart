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
    final m2 = m1.update(0, (value) => value + 1, ifAbsent: () => 0);
    IMap<int, int>? lastRes;
    final sub = m2.snapshot.listen((event) {
      lastRes = event;
    });
    await Future.value();
    // The extra microtask lags are due to .update subscribing the parent's [key]
    await Future.value();
    expect(lastRes, {0: 0}.lock);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(lastRes, {0: 2}.lock);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(lastRes, {0: 0}.lock);
    s.add(KeyChanges({1: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(lastRes, {0: 0, 1: 1}.lock);
    s.add(ChangeEventReplace({0: 1, 1: 2}.lock));
    await Future.value();
    expect(lastRes, {0: 2, 1: 2}.lock);
    s.add(ChangeEventReplace({1: 2}.lock));
    await Future.value();
    expect(lastRes, {0: 0, 1: 2}.lock);

    sub.cancel();
  });

  test(
      'snapshot, operator[] throws if the key does not exist and no ifAbsent is given',
      () async {
    final m1 = IComputedMap(<int, int>{}.lock);
    final m2 = m1.update(0, (v) => v);

    for (var c in [
      m2[0],
      m2.length,
      m2.isEmpty,
      m2.isNotEmpty,
      m2.containsKey(0),
      m2.containsValue(0),
      m2.snapshot
    ]) {
      Object? lastExc;
      var cnt = 0;

      final sub = c.listen((event) => fail('Must never report a value'), (e) {
        cnt++;
        lastExc = e;
      });
      await Future.value();
      await Future.value();

      expect(cnt, 1);
      expect(lastExc.toString(),
          ArgumentError.value(0, "key", "Key not in map.").toString());

      sub.cancel();
    }
  });

  test('operator[] works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.update(0, (v) => v + 1, ifAbsent: () => 0);

    var callCnt1 = 0;
    int? lastRes1;
    final sub1 = m2[0].listen((event) {
      callCnt1++;
      lastRes1 = event;
    });

    var callCnt2 = 0;
    int? lastRes2;
    final sub2 = m2[1].listen((event) {
      callCnt2++;
      lastRes2 = event;
    });

    expect(callCnt1, 0);
    expect(callCnt2, 0);
    await Future.value();
    await Future.value();
    expect(callCnt1, 1);
    expect(lastRes1, 0);
    expect(callCnt2, 1);
    expect(lastRes2, null);

    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(callCnt1, 2);
    expect(lastRes1, 2);
    expect(callCnt2, 1);

    s.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    await Future.value();
    expect(callCnt1, 2);
    expect(callCnt2, 2);
    expect(lastRes2, 2);

    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(callCnt1, 3);
    expect(lastRes1, 0);
    expect(callCnt2, 2);

    s.add(ChangeEventReplace({1: 0}.lock));
    await Future.value();
    expect(callCnt1, 3);
    expect(callCnt2, 3);
    expect(lastRes2, 0);

    s.add(ChangeEventReplace({0: 0, 1: 1}.lock));
    await Future.value();
    expect(callCnt1, 4);
    expect(lastRes1, 1);
    expect(callCnt2, 4);
    expect(lastRes2, 1);

    sub1.cancel();
    sub2.cancel();

    s.add(ChangeEventReplace(<int, int>{}.lock));
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callCnt1, 4); // The listeners have been cancelled
    expect(callCnt2, 4);
  });

  test('change stream throws if the key gets deleted and no ifAbsent is given',
      () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.update(0, (v) => v);

    Object? lastExc;
    var cnt = 0;

    final sub =
        m2.changes.listen((event) => fail('Must never report a value'), (e) {
      cnt++;
      lastExc = e;
    });
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    await Future.value();

    expect(cnt, 1);
    expect(lastExc.toString(),
        ArgumentError.value(0, "key", "Key not in map.").toString());

    sub.cancel();
  });

  test('propagates the change stream', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.update(0, (value) => value + 1, ifAbsent: () => 0);
    ChangeEvent<int, int>? lastRes;
    final sub = m2.changes.listen((event) {
      lastRes = event;
    });
    await Future.value();
    await Future.value();
    expect(lastRes, null);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(lastRes, KeyChanges({0: ChangeRecordValue(2)}.lock));
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(lastRes, KeyChanges({0: ChangeRecordValue(0)}.lock));
    s.add(KeyChanges({1: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(lastRes, KeyChanges({1: ChangeRecordValue(1)}.lock));
    s.add(ChangeEventReplace({0: 1, 1: 2}.lock));
    await Future.value();
    expect(lastRes, ChangeEventReplace({0: 2, 1: 2}.lock));
    s.add(ChangeEventReplace({1: 2}.lock));
    await Future.value();
    expect(lastRes, ChangeEventReplace({0: 0, 1: 2}.lock));
    s.add(KeyChanges(<int, ChangeRecord<int>>{}.lock));
    await Future.value();
    expect(lastRes, ChangeEventReplace({0: 0, 1: 2}.lock)); // No change

    sub.cancel();
  });

  test('attributes are coherent', () async {
    final m = IComputedMap({0: 1}.lock);
    final a = m.update(0, (v) => v + 1);
    final b = a.update(1, (v) => v + 1, ifAbsent: () => 42);
    await testCoherenceInt(a, {0: 2}.lock);
    await testCoherenceInt(b, {0: 2, 1: 42}.lock);
  });
}
