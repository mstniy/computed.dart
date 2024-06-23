import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/const_computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('incremental update works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.groupBy((_, v) => v % 3); // Divide into three groups
    IMap<int, IComputedMap<int, int>>? lastRes1;
    final sub1 = m2.snapshot.listen((event) {
      lastRes1 = event;
    }, null);
    IMap<int, int>? lastRes2;
    final sub2 = $(() => m2.snapshot.use[0]?.snapshot.use).listen((event) {
      lastRes2 = event;
    }, null);
    IMap<int, int>? lastRes3;
    final sub3 = $(() => m2.snapshot.use[1]?.snapshot.use).listen((event) {
      lastRes3 = event;
    }, null);
    IMap<int, int>? lastRes4;
    final sub4 = $(() => m2.snapshot.use[2]?.snapshot.use).listen((event) {
      lastRes4 = event;
    }, null);
    ChangeEvent<int, int>? lastRes5;
    final sub5 = $(() => m2.snapshot.use[0]?.changes.use).listen((event) {
      lastRes5 = event;
    }, null);
    await Future.value();
    expect(lastRes1, {}.lock);
    for (var i = 0; i < 5; i++) {
      await Future.value();
    }
    expect(lastRes2, null);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, null);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock)); // Add a new group
    await Future.value();
    expect(lastRes1!.keys, [1]);
    expect(lastRes2, null);
    expect(lastRes3, {0: 1}.lock);
    expect(lastRes4, null);
    expect(lastRes5, null);
    // Change the value of an existing item, removing a group
    // + add a new group
    s.add(KeyChanges({0: ChangeRecordValue(2), 1: ChangeRecordValue(0)}.lock));
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 2]));
    expect(lastRes2, {1: 0}.lock);
    expect(lastRes3, null);
    expect(lastRes4, {0: 2}.lock);
    expect(lastRes5, null); // No changes, as the group just got created
    // Change the value of an existing item, while preserving its group
    // + Remove a group by removing an item
    s.add(KeyChanges(
        {0: ChangeRecordDelete<int>(), 1: ChangeRecordValue(3)}.lock));
    expect(lastRes1!.keys, [0]);
    await Future
        .value(); // Wait for the microtask delay of the internal StreamController
    expect(lastRes2, {1: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, KeyChanges({1: ChangeRecordValue(3)}.lock));
    // Add a value to an existing group
    s.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    expect(lastRes1!.keys, [0]);
    await Future.value();
    expect(lastRes2, {0: 0, 1: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, KeyChanges({0: ChangeRecordValue(0)}.lock));
    // Remove a value from an existing group, which has other elements
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes1!.keys, [0]);
    await Future.value();
    expect(lastRes2, {1: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    // Upstream replacement
    s.add(ChangeEventReplace({0: 0, 1: 1, 2: 3}.lock));
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 1]));
    expect(lastRes2, {0: 0, 2: 3}.lock);
    expect(lastRes3, {1: 1}.lock);
    expect(lastRes4, null);
    expect(
        lastRes5,
        KeyChanges({
          0: ChangeRecordDelete<int>()
        }.lock)); // No new change event, as the group got replaced with a new one
    // Change the group of an item, changing its group, but keeping its former group populated
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(lastRes1!.keys, unorderedEquals([0, 1]));
    await Future.value();
    expect(lastRes2, {2: 3}.lock);
    expect(lastRes3, {0: 1, 1: 1}.lock);
    expect(lastRes4, null);
    expect(
        lastRes5,
        KeyChanges({0: ChangeRecordDelete<int>()}
            .lock)); // Happens to be the same as the last event
    // Delete a key, removing a group, but a new key immediately re-creates it
    s.add(KeyChanges(
        {2: ChangeRecordDelete<int>(), 0: ChangeRecordValue(3)}.lock));
    expect(lastRes1!.keys, unorderedEquals([0, 1]));
    await Future.value();
    await Future.value();
    expect(lastRes2, {0: 3}.lock);
    expect(lastRes3, {1: 1}.lock);
    expect(lastRes4, null);
    expect(
        lastRes5,
        KeyChanges(
            {0: ChangeRecordValue(3), 2: ChangeRecordDelete<int>()}.lock));
    // Make multiple changes to groups in one upstream change
    s.add(KeyChanges({
      2: ChangeRecordValue(1),
      1: ChangeRecordValue(3),
      0: ChangeRecordValue(1),
      3: ChangeRecordValue(0),
      4: ChangeRecordValue(0)
    }.lock));
    expect(lastRes1!.keys, unorderedEquals([0, 1]));
    await Future.value();
    expect(lastRes2, {1: 3, 3: 0, 4: 0}.lock);
    expect(lastRes3, {0: 1, 2: 1}.lock);
    expect(lastRes4, null);
    expect(
        lastRes5,
        KeyChanges({
          0: ChangeRecordDelete<int>(),
          1: ChangeRecordValue(3),
          3: ChangeRecordValue(0),
          4: ChangeRecordValue(0),
        }.lock));

    // Multiple upstream deletions leading to a group being deleted
    s.add(KeyChanges({
      0: ChangeRecordDelete<int>(),
      1: ChangeRecordDelete<int>(),
      2: ChangeRecordDelete<int>(),
      3: ChangeRecordDelete<int>(),
    }.lock));
    expect(lastRes1!.keys, unorderedEquals([0]));
    await Future.value();
    expect(lastRes2, {4: 0}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(
        lastRes5,
        KeyChanges({
          1: ChangeRecordDelete<int>(),
          3: ChangeRecordDelete<int>(),
        }.lock));

    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
    sub4.cancel();
    sub5.cancel();
  });

  test('initial computation works', () async {
    final m1 = ConstComputedMap({0: 1, 1: 2, 2: 3, 3: 4}.lock);
    final m2 = m1.groupBy((key, value) => key % 3);
    expect((await getValue(m2.snapshot)).keys, unorderedEquals([0, 1, 2]));
  });
  test('operator[] works', () async {
    final m1 = ConstComputedMap({0: 1, 1: 2, 2: 3, 3: 4}.lock);
    final m2 = m1.groupBy((key, value) => key % 3);
    final group0 = m2[0];
    expect(
        (await getValue($(() => group0.use!.snapshot.use))), {0: 1, 3: 4}.lock);
    m1.mock(ConstComputedMap({0: 1, 1: 2, 2: 3}.lock));
    expect((await getValue($(() => group0.use!.snapshot.use))), {0: 1}.lock);
    m1.mock(ConstComputedMap({1: 2, 2: 3}.lock));
    expect((await getValue($(() => group0.use))), null);
  });

  test('containsKey works', () async {
    final m1 = ConstComputedMap({0: 1, 1: 2}.lock);
    final m2 = m1.groupBy((key, value) => key % 3);
    expect(await getValue(m2.containsKey(0)), true);
    expect(await getValue(m2.containsKey(1)), true);
    expect(await getValue(m2.containsKey(2)), false);
  });

  test('containsValue works', () async {
    // The semantics here are admittedly somehow unintuitive
    // It is worth nothing that a "value" from the perspective of the groupBy collection
    // is itself a collection representing the group.
    final m1 = ConstComputedMap({0: 1, 1: 2}.lock);
    final m2 = m1.groupBy((key, value) => key % 3);
    // We have to maintain a listener on m2 - otherwise it creates new group collections with each getValue call
    final sub = m2.snapshot.listen((event) {}, null);
    final group = (await getValue(m2[0]))!;
    expect(await getValue(m2.containsValue(group)), true);
    expect(
        await getValue(m2.containsValue(
            IComputedMap.fromChangeStream($(() => throw NoValueException())))),
        false);

    sub.cancel();
  });

  test('fix/mock works', () async {
    final m1 = ConstComputedMap(<int, int>{}.lock);
    final m2 = m1.groupBy((key, value) => 0);

    final group = ConstComputedMap({1: 2}.lock);

    m2.fix({0: group}.lock);

    await testCoherence(
        m2, {0: group}.lock, 1, ConstComputedMap(<int, int>{}.lock));

    m2.mock(ConstComputedMap({1: group}.lock));

    await testCoherence(
        m2, {1: group}.lock, 0, ConstComputedMap(<int, int>{}.lock));

    m2.unmock();

    await testCoherence(m2, <int, IComputedMap<int, int>>{}.lock, 0,
        ConstComputedMap(<int, int>{}.lock));
  });
}
