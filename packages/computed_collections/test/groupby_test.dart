import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/const_computedmap.dart';
import 'package:computed_collections/src/ss_computedmap.dart';
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
    ChangeEvent<int, IComputedMap<int, int>>? lastRes6;
    final sub6 = m2.changes.listen((event) {
      lastRes6 = event;
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
    expect(lastRes6, null);

    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock)); // Add a new group
    expect(lastRes1!.keys, [1]);
    expect(lastRes2, null);
    expect(lastRes3, {0: 1}.lock);
    expect(lastRes4, null);
    expect(lastRes5, null);
    expect(lastRes6, KeyChanges({1: ChangeRecordValue(lastRes1![1])}.lock));

    // Change the value of an existing item, removing a group
    // + add a new group
    s.add(KeyChanges({0: ChangeRecordValue(2), 1: ChangeRecordValue(0)}.lock));
    expect(lastRes1!.keys, unorderedEquals([0, 2]));
    expect(lastRes2, {1: 0}.lock);
    expect(lastRes3, null);
    expect(lastRes4, {0: 2}.lock);
    expect(lastRes5, null); // No changes, as the group just got created
    expect(
        lastRes6,
        KeyChanges({
          0: ChangeRecordValue(lastRes1![0]!),
          2: ChangeRecordValue(lastRes1![2]!),
          1: ChangeRecordDelete<IComputedMap<int, int>>()
        }.lock));

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
    expect(lastRes6,
        KeyChanges({2: ChangeRecordDelete<IComputedMap<int, int>>()}.lock));

    // Add a value to an existing group
    s.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    expect(lastRes1!.keys, [0]);
    expect(lastRes2, {0: 0, 1: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, KeyChanges({0: ChangeRecordValue(0)}.lock));
    // No change
    expect(lastRes6,
        KeyChanges({2: ChangeRecordDelete<IComputedMap<int, int>>()}.lock));

    // Remove a value from an existing group, which has other elements
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes1!.keys, [0]);
    expect(lastRes2, {1: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    // No change
    expect(lastRes6,
        KeyChanges({2: ChangeRecordDelete<IComputedMap<int, int>>()}.lock));

    // Re-introduce a previously removed group
    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(lastRes1!.keys, [0, 2]);
    expect(lastRes2, {1: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, {0: 2}.lock);
    // No change
    expect(lastRes5, KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes6, KeyChanges({2: ChangeRecordValue(lastRes1![2])}.lock));

    // Upstream replacement
    s.add(ChangeEventReplace({0: 0, 1: 1, 2: 3}.lock));
    expect(lastRes1!.keys, unorderedEquals([0, 1]));
    expect(lastRes2, {0: 0, 2: 3}.lock);
    expect(lastRes3, {1: 1}.lock);
    expect(lastRes4, null);
    expect(
        lastRes5,
        KeyChanges({
          0: ChangeRecordDelete<int>()
        }.lock)); // No new change event, as the group got replaced with a new one
    expect(lastRes6,
        ChangeEventReplace({0: lastRes1![0]!, 1: lastRes1![1]!}.lock));

    // Change the group of an item, changing its group, but keeping its former group populated
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(lastRes1!.keys, unorderedEquals([0, 1]));
    expect(lastRes2, {2: 3}.lock);
    expect(lastRes3, {0: 1, 1: 1}.lock);
    expect(lastRes4, null);
    expect(
        lastRes5,
        KeyChanges({0: ChangeRecordDelete<int>()}
            .lock)); // Happens to be the same as the last event
    // No change
    expect(lastRes6,
        ChangeEventReplace({0: lastRes1![0]!, 1: lastRes1![1]!}.lock));

    // Delete a key, removing a group, but a new key immediately re-creates it
    s.add(KeyChanges(
        {2: ChangeRecordDelete<int>(), 0: ChangeRecordValue(3)}.lock));
    expect(lastRes1!.keys, unorderedEquals([0, 1]));
    expect(lastRes2, {0: 3}.lock);
    expect(lastRes3, {1: 1}.lock);
    expect(lastRes4, null);
    expect(
        lastRes5,
        KeyChanges(
            {0: ChangeRecordValue(3), 2: ChangeRecordDelete<int>()}.lock));
    // No change
    expect(lastRes6,
        ChangeEventReplace({0: lastRes1![0]!, 1: lastRes1![1]!}.lock));

    // Make multiple changes to groups in one upstream change
    s.add(KeyChanges({
      2: ChangeRecordValue(1),
      1: ChangeRecordValue(3),
      0: ChangeRecordValue(1),
      3: ChangeRecordValue(0),
      4: ChangeRecordValue(0)
    }.lock));
    expect(lastRes1!.keys, unorderedEquals([0, 1]));
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
    // No change
    expect(lastRes6,
        ChangeEventReplace({0: lastRes1![0]!, 1: lastRes1![1]!}.lock));

    // Multiple upstream deletions leading to a group being deleted
    s.add(KeyChanges({
      0: ChangeRecordDelete<int>(),
      1: ChangeRecordDelete<int>(),
      2: ChangeRecordDelete<int>(),
      3: ChangeRecordDelete<int>(),
    }.lock));
    expect(lastRes1!.keys, unorderedEquals([0]));
    expect(lastRes2, {4: 0}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(
        lastRes5,
        KeyChanges({
          1: ChangeRecordDelete<int>(),
          3: ChangeRecordDelete<int>(),
        }.lock));
    expect(lastRes6,
        KeyChanges({1: ChangeRecordDelete<IComputedMap<int, int>>()}.lock));

    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
    sub4.cancel();
    sub5.cancel();
    sub6.cancel();
  });

  test('initial computation works', () async {
    final m1 = ConstComputedMap({0: 1, 1: 2, 2: 3, 3: 4}.lock);
    final m2 = m1.groupBy((key, value) => key % 3);
    expect((await getValue(m2.snapshot)).keys, unorderedEquals([0, 1, 2]));
  });
  test('operator[] works', () async {
    final s = ValueStream.seeded({0: 1, 1: 2, 2: 3, 3: 4}.lock);
    final m1 = SnapshotStreamComputedMap($(() => s.use));
    final m2 = m1.groupBy((key, value) => key % 3);
    final group0 = m2[0];
    expect(
        (await getValue($(() => group0.use!.snapshot.use))), {0: 1, 3: 4}.lock);
    s.add({0: 1, 1: 2, 2: 3}.lock);
    expect((await getValue($(() => group0.use!.snapshot.use))), {0: 1}.lock);
    s.add({1: 2, 2: 3}.lock);
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

  test('is(Not)Empty/length works', () async {
    final m1 = ConstComputedMap({0: 1, 1: 2, 2: 3}.lock)
        .groupBy((key, value) => key % 2);
    expect(await getValue(m1.length), 2);
    expect(await getValue(m1.isEmpty), false);
    expect(await getValue(m1.isNotEmpty), true);

    final m2 = ConstComputedMap({}.lock).groupBy((key, value) => key % 2);
    expect(await getValue(m2.length), 0);
    expect(await getValue(m2.isEmpty), true);
    expect(await getValue(m2.isNotEmpty), false);
  });

  test('propagates exceptions', () async {
    final s = ValueStream<ChangeEvent<int, int>>.seeded(
        ChangeEventReplace({0: 1}.lock),
        sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.groupBy((key, value) => key);

    List<Object?> res = [null, null, null, null];
    final x = [
      m2.changes.listen((e) => null, (o) => res[0] = o),
      m2.snapshot.listen((e) => null, (o) => res[1] = o),
      $(() => m2[0].use?.changes.use).listen((e) => null, (o) => res[2] = o),
      $(() => m2[0].use?.snapshot.use).listen((e) => null, (o) => res[3] = o),
    ];
    await Future.value();
    s.addError(42);
    res.forEach((o) => expect(o, 42));
    s.addError(43); // Has no effect due to the "cancelOnError" semantics
    for (var i = 0; i < 5; i++) await Future.value();
    res.forEach((o) => expect(o, 42)); // And not 43
    x.forEach((sub) => sub.cancel());
  });

  test('listening on snapshot when there already are listeners and groups',
      () async {
    final m =
        IComputedMap({0: 1, 1: 2, 2: 3}.lock).groupBy((key, value) => key % 2);

    final sub = m.changes.listen(null);
    await Future.value();

    expect((await getValue(m.snapshot)).keys, [0, 1]);

    sub.cancel();
  });

  test(
      'listening on snapshot when there already are listeners and upstream has reported an exception',
      () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.groupBy((key, value) => key);

    Object? exc1;
    int cnt1 = 0;
    final sub1 = m2.changes.listen((e) => fail('Must never be called'), (o) {
      cnt1++;
      exc1 = o;
    });
    await Future.value();
    s.addError(42);
    expect(cnt1, 1);
    expect(exc1, 42);

    Object? exc2;
    int cnt2 = 0;
    final sub2 = m2.snapshot.listen((e) => fail('Must never be called'), (o) {
      cnt2++;
      exc2 = o;
    });
    await Future.value();
    expect(cnt1, 1);
    expect(cnt2, 1);
    expect(exc2, 42);

    sub1.cancel();
    sub2.cancel();
  });

  test('defunct computations stop computing', () async {
    final s = ValueStream<IMap<int, int>>.seeded({0: 1}.lock, sync: true);
    final m1 = IComputedMap.fromSnapshotStream($(() => s.use));
    final m2 = m1.groupBy((key, value) => key);
    final defunct = (await getValue(m2[0]))!;
    expect(await getValues(defunct.snapshot), []);
    expect(await getValues(defunct.changes), []);
    expect(
        await getValuesWhile(defunct.snapshot, () async {
          final sub = m2.snapshot.listen(null);
          await Future.value();
          sub.cancel();
        }),
        []);
    expect(
        await getValuesWhile(defunct.changes, () async {
          final sub = m2.snapshot.listen(null);
          await Future.value();
          sub.cancel();
        }),
        []);
  });

  test('handles upstream extraneous deletions', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s.use));
    final m2 = m1.groupBy((key, value) => key);

    IMap<int, IComputedMap<int, int>>? snap;
    final sub = m2.snapshot.listen((event) => snap = event);
    await Future.value();
    s.add(ChangeEventReplace({0: 1, 1: 2, 2: 3}.lock));
    expect(snap!.keys, [0, 1, 2]);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(snap!.keys, [1, 2]);
    s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(snap!.keys, [2]);
    // Send an extraneous deletion
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(snap!.keys, [2]);
    // Still reactive
    s.add(KeyChanges({2: ChangeRecordDelete<int>()}.lock));
    expect(snap!.keys, []);

    sub.cancel();
  });
}
