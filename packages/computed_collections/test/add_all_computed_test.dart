import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('initial computation works', () async {
    final x = ComputedMap({0: 1, 1: 2}.lock);
    final y = x.addAllComputed(ComputedMap({1: 3, 2: 4}.lock));
    expect(await getValue(y.snapshot), {0: 1, 1: 3, 2: 4}.lock);
  });

  test('containsKey works', () async {
    final x = ComputedMap({0: 1, 1: 2}.lock);
    final y = x.addAllComputed(ComputedMap({1: 3, 2: 4}.lock));
    expect(await getValue(y.containsKey(0)), true);
    expect(await getValue(y.containsKey(1)), true);
    expect(await getValue(y.containsKey(2)), true);
    expect(await getValue(y.containsKey(3)), false);
  });

  test('containsValue works', () async {
    final x = ComputedMap({0: 1, 1: 4}.lock);
    final y = x.addAllComputed(ComputedMap({1: 3, 2: 4}.lock));
    expect(await getValue(y.containsValue(1)), true);
    expect(await getValue(y.containsValue(3)), true);
    expect(await getValue(y.containsValue(4)), true);
    expect(await getValue(y.containsValue(5)), false);
  });

  test('operator[] works', () async {
    final x = ComputedMap({0: 1, 1: 2}.lock);
    final y = x.addAllComputed(ComputedMap({1: 3, 2: 4}.lock));
    expect(await getValue(y[0]), 1);
    expect(await getValue(y[1]), 3);
    expect(await getValue(y[2]), 4);
    expect(await getValue(y[3]), null);
  });

  test('isEmpty works', () async {
    expect(
        await getValue(ComputedMap(<int, int>{}.lock)
            .addAllComputed(ComputedMap(<int, int>{}.lock))
            .isEmpty),
        true);
    expect(
        await getValue(ComputedMap({0: 1}.lock)
            .addAllComputed(ComputedMap(<int, int>{}.lock))
            .isEmpty),
        false);
    expect(
        await getValue(ComputedMap(<int, int>{}.lock)
            .addAllComputed(ComputedMap({0: 1}.lock))
            .isEmpty),
        false);
    expect(
        await getValue(ComputedMap({0: 1}.lock)
            .addAllComputed(ComputedMap({0: 1}.lock))
            .isEmpty),
        false);
  });

  test('isNotEmpty works', () async {
    expect(
        await getValue(ComputedMap(<int, int>{}.lock)
            .addAllComputed(ComputedMap(<int, int>{}.lock))
            .isNotEmpty),
        false);
    expect(
        await getValue(ComputedMap({0: 1}.lock)
            .addAllComputed(ComputedMap(<int, int>{}.lock))
            .isNotEmpty),
        true);
    expect(
        await getValue(ComputedMap(<int, int>{}.lock)
            .addAllComputed(ComputedMap({0: 1}.lock))
            .isNotEmpty),
        true);
    expect(
        await getValue(ComputedMap({0: 1}.lock)
            .addAllComputed(ComputedMap({0: 1}.lock))
            .isNotEmpty),
        true);
  });

  test('propagates the change stream 1', () async {
    final s = StreamController<
        (ChangeEvent<int, int>, ChangeEvent<int, int>)>.broadcast(sync: true);
    final s2 = s.stream;
    final x = ComputedMap.fromChangeStream($(() => s2.use.$1));
    final y = ComputedMap.fromChangeStream($(() => s2.use.$2));
    final z = x.addAllComputed(y);

    ChangeEvent<int, int>? lastRes;
    var callCnt = 0;
    final sub = z.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    for (var i = 0; i < 5; i++) await Future.value();
    expect(callCnt, 0);
    s.add((
      ChangeEventReplace({0: 0, 1: 1, 2: 2}.lock),
      KeyChanges({
        1: ChangeRecordValue(2),
        2: ChangeRecordDelete<int>(),
        3: ChangeRecordValue(3),
        4: ChangeRecordDelete<int>()
      }.lock)
    ));
    expect(callCnt, 1);
    expect(lastRes, ChangeEventReplace({0: 0, 1: 2, 2: 2, 3: 3}.lock));

    s.add((
      ChangeEventReplace({0: 1, 1: 3, 2: 4}.lock),
      KeyChanges({
        // No change
        1: ChangeRecordValue(2),
        2: ChangeRecordDelete<int>(),
        3: ChangeRecordValue(3),
        4: ChangeRecordDelete<int>()
      }.lock)
    ));
    expect(callCnt, 2);
    expect(lastRes, ChangeEventReplace({0: 1, 1: 2, 2: 4, 3: 3}.lock));

    s.add((
      KeyChanges({1: ChangeRecordValue(4), 2: ChangeRecordDelete<int>()}.lock),
      ChangeEventReplace({0: 0, 2: 2}.lock)
    ));
    expect(callCnt, 3);
    expect(lastRes, ChangeEventReplace({0: 0, 1: 4, 2: 2}.lock));

    s.add((
      KeyChanges({
        0: ChangeRecordDelete<int>(),
        1: ChangeRecordValue(3),
        2: ChangeRecordValue(3)
      }.lock),
      ChangeEventReplace({0: 0, 2: 2}.lock) // No change
    ));
    expect(callCnt, 4);
    expect(lastRes, KeyChanges({1: ChangeRecordValue(3)}.lock));

    s.add((
      KeyChanges({
        0: ChangeRecordDelete<int>(),
        1: ChangeRecordValue(3),
        2: ChangeRecordValue(3)
      }.lock), // No change
      ChangeEventReplace({0: 0, 1: 2, 3: 3}.lock)
    ));
    expect(callCnt, 5);
    expect(lastRes, ChangeEventReplace({0: 0, 1: 2, 2: 3, 3: 3}.lock));

    s.add((
      KeyChanges({
        0: ChangeRecordDelete<int>(),
        1: ChangeRecordValue(3),
        2: ChangeRecordValue(3)
      }.lock), // No change
      KeyChanges({
        0: ChangeRecordDelete<int>(),
        1: ChangeRecordDelete<int>(),
        2: ChangeRecordValue(2),
        3: ChangeRecordValue(4)
      }.lock)
    ));
    expect(callCnt, 6);
    expect(
        lastRes,
        KeyChanges({
          0: ChangeRecordDelete<int>(),
          1: ChangeRecordValue(3),
          2: ChangeRecordValue(2),
          3: ChangeRecordValue(4)
        }.lock));

    s.add((
      ChangeEventReplace({0: 0, 1: 1}.lock),
      ChangeEventReplace({1: 2, 2: 3}.lock)
    ));
    expect(callCnt, 7);
    expect(lastRes, ChangeEventReplace({0: 0, 1: 2, 2: 3}.lock));

    s.add((
      KeyChanges({0: ChangeRecordValue(1), 2: ChangeRecordValue(2)}.lock),
      KeyChanges({1: ChangeRecordDelete<int>(), 3: ChangeRecordValue(3)}.lock),
    ));
    expect(callCnt, 8);
    expect(
        lastRes,
        KeyChanges({
          0: ChangeRecordValue(1),
          1: ChangeRecordValue(1),
          3: ChangeRecordValue(3),
        }.lock));

    s.add((
      KeyChanges(<int, ChangeRecord<int>>{}.lock),
      KeyChanges(<int, ChangeRecord<int>>{}.lock),
    ));
    expect(callCnt, 8); // No change

    sub.cancel();
  });

  test('propagates the change stream 2', () async {
    final s = StreamController<ChangeEvent<int, int>>.broadcast(sync: true);
    final stream = s.stream;
    final c1 = ComputedMap(<int, int>{1: 1}.lock);
    final c2 = ComputedMap.fromChangeStream($(() => stream.use));
    final c3 = c1.addAllComputed(c2);

    ChangeEvent<int, int>? lastRes;
    var callCnt = 0;
    final sub = c3.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    for (var i = 0; i < 5; i++) await Future.value();
    expect(callCnt, 0);

    s.add(KeyChanges({0: ChangeRecordValue(1), 1: ChangeRecordValue(2)}.lock));
    expect(callCnt, 1);
    expect(lastRes,
        KeyChanges({0: ChangeRecordValue(1), 1: ChangeRecordValue(2)}.lock));

    s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(callCnt, 2);
    expect(lastRes, KeyChanges({1: ChangeRecordValue(1)}.lock));

    sub.cancel();
  });

  test('attributes are coherent', () async {
    final x = ComputedMap({0: 1, 1: 2}.lock);
    final y = x.addAllComputed(ComputedMap({1: 3, 2: 4}.lock));
    await testCoherenceInt(y, {0: 1, 1: 3, 2: 4}.lock);
  });
}
