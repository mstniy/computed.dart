import 'dart:async';

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
    final s1 = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s1.use));
    // Make different elements' groups depend on different data sources, because why not
    final lookups =
        List.generate(2, (_) => ValueStream<IList<int>>(sync: true));
    final m2 = m1.groupByComputed((k, v) => $(() => lookups[k % 3].use[v % 3]));
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
    ChangeEvent<int, int>? lastRes6;
    final sub6 = $(() => m2.snapshot.use[1]?.changes.use).listen((event) {
      lastRes6 = event;
    }, null);
    ChangeEvent<int, int>? lastRes7;
    final sub7 = $(() => m2.snapshot.use[2]?.changes.use).listen((event) {
      lastRes7 = event;
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
    expect(lastRes7, null);
    s1.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    // This by itself causes no change on the collection, as the group computation has no value yet
    for (var i = 0; i < 5; i++) {
      await Future.value();
    }
    expect(lastRes1, {}.lock);
    expect(lastRes2, null);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, null);
    expect(lastRes6, null);
    expect(lastRes7, null);
    // This adds a new group
    lookups[0].add([0, 1, 2].lock);
    await Future.value();
    expect(lastRes1!.keys, [1]);
    await Future.value();
    expect(lastRes2, null);
    expect(lastRes3, {0: 1}.lock);
    expect(lastRes4, null);
    expect(lastRes5, null);
    expect(lastRes6, null); // Just got created
    expect(lastRes7, null);
    // Change the group of an existing item, removing a group
    // + add a new group
    lookups[0].add([1, 2, 2].lock);
    await Future.value();
    expect(lastRes1!.keys, [2]);
    await Future.value();
    expect(lastRes2, null);
    expect(lastRes3, null);
    expect(lastRes4, {0: 1}.lock);
    expect(lastRes5, null);
    expect(lastRes6, null); // The group is gone
    expect(lastRes7, null); // The group just got created
    // Change the value of an existing item, while preserving its group
    s1.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    await Future.value();
    expect(lastRes1!.keys, [2]);
    await Future.value();
    expect(lastRes2, null);
    expect(lastRes3, null);
    expect(lastRes4, {0: 2}.lock);
    expect(lastRes5, null);
    expect(lastRes6, null);
    expect(lastRes7,
        null); // The group got removed and re-created behind the scenes
    // Remove a group by removing the only element in it
    // And add a new element upstream, creating a new group
    lookups[1].add([0, 0, 2].lock);
    s1.add(KeyChanges(
        {0: ChangeRecordDelete<int>(), 1: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(lastRes1!.keys, [0]);
    await Future.value();
    expect(lastRes2, {1: 1}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, null); // No change yet as the group just got created
    expect(lastRes6, null);
    expect(lastRes7, null); // The group is gone
    // Add a value to an existing group
    s1.add(KeyChanges({4: ChangeRecordValue(0)}.lock));
    expect(lastRes1!.keys, [0]);
    await Future.value();
    await Future.value();
    expect(lastRes2, {1: 1, 4: 0}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, KeyChanges({4: ChangeRecordValue(0)}.lock));
    expect(lastRes6, null);
    expect(lastRes7, null);
    // Remove a value from an existing group, which has other elements
    s1.add(KeyChanges({4: ChangeRecordDelete<int>()}.lock));
    expect(lastRes1!.keys, [0]);
    await Future.value();
    expect(lastRes2, {1: 1}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    expect(lastRes5, KeyChanges({4: ChangeRecordDelete<int>()}.lock));
    expect(lastRes6, null);
    expect(lastRes7, null);
    // Upstream replacement
    s1.add(ChangeEventReplace({0: 0, 1: 1, 3: 2, 4: 0}.lock));
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 1, 2]));
    await Future.value();
    expect(lastRes2, {1: 1, 4: 0}.lock);
    expect(lastRes3, {0: 0}.lock);
    expect(lastRes4, {3: 2}.lock);
    // This is "stuck" at its previous value as the new group collection's change stream is empty now
    // This also demonstrates that this is not a reliable way of tracking the changes to a group
    expect(lastRes5, KeyChanges({4: ChangeRecordDelete<int>()}.lock));
    expect(lastRes6, null); // Just got created
    expect(lastRes7, null); // Just got created
    // Change the group of an item, changing its group, but keeping its former group populated
    s1.add(KeyChanges({1: ChangeRecordValue(2)}.lock));
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 1, 2]));
    await Future.value();
    expect(lastRes2, {4: 0}.lock);
    expect(lastRes3, {0: 0}.lock);
    expect(lastRes4, {3: 2, 1: 2}.lock);
    expect(lastRes5, KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(lastRes6, null); // No changes still
    expect(lastRes7,
        KeyChanges({1: ChangeRecordValue(2)}.lock)); // Just got created
    // Delete a key, removing a group, but a new key immediately re-creates it
    s1.add(KeyChanges(
        {0: ChangeRecordDelete<int>(), 6: ChangeRecordValue(0)}.lock));
    await Future.value();
    await Future.value();
    await Future.value();
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 1, 2]));
    await Future.value();
    expect(lastRes2, {4: 0}.lock);
    expect(lastRes3, {6: 0}.lock);
    expect(lastRes4, {3: 2, 1: 2}.lock);
    expect(lastRes5, KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(lastRes6, null); // No changes still
    expect(
        lastRes7, KeyChanges({1: ChangeRecordValue(2)}.lock)); // No new change
    // Make multiple changes to groups in one upstream change
    s1.add(KeyChanges({
      1: ChangeRecordValue(1),
      3: ChangeRecordValue(3),
      4: ChangeRecordValue(2),
      6: ChangeRecordDelete<int>(),
      7: ChangeRecordValue(2),
      9: ChangeRecordValue(1)
    }.lock));
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 1, 2]));
    await Future.value();
    expect(lastRes2, {1: 1}.lock);
    expect(lastRes3, {3: 3}.lock);
    expect(lastRes4, {4: 2, 7: 2, 9: 1}.lock);
    // This is stuck again, as the group just got re-created, thus has no change yet
    expect(lastRes5, KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(lastRes6, null); // The group got recreated
    // The group got re-created, so no new changes
    expect(lastRes7, KeyChanges({1: ChangeRecordValue(2)}.lock));

    // Change the grouping
    lookups[0].add([0, 2, 2].lock);
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 2]));
    expect(lastRes2, {1: 1, 3: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, {4: 2, 7: 2, 9: 1}.lock);
    expect(lastRes5, KeyChanges({3: ChangeRecordValue(3)}.lock));
    expect(lastRes6, null); // The group got deleted
    // Still no changes
    expect(lastRes7, KeyChanges({1: ChangeRecordValue(2)}.lock));

    s1.add(KeyChanges({10: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 2]));
    await Future.value();
    expect(lastRes2, {1: 1, 3: 3, 10: 1}.lock);
    expect(lastRes3, null);
    expect(lastRes4, {4: 2, 7: 2, 9: 1}.lock);
    expect(lastRes5, KeyChanges({10: ChangeRecordValue(1)}.lock));
    expect(lastRes6, null); // No change
    // Still no changes
    expect(lastRes7, KeyChanges({1: ChangeRecordValue(2)}.lock));

    s1.add(KeyChanges({
      1: ChangeRecordValue(0),
      3: ChangeRecordValue(0),
      4: ChangeRecordDelete<int>(),
      7: ChangeRecordDelete<int>()
    }.lock));
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 2]));
    await Future.value();
    expect(lastRes2, {1: 0, 3: 0, 10: 1}.lock);
    expect(lastRes3, null);
    expect(lastRes4, {9: 1}.lock);
    expect(lastRes5,
        KeyChanges({1: ChangeRecordValue(0), 3: ChangeRecordValue(0)}.lock));
    expect(lastRes6, null); // No change
    // Still no changes
    expect(
        lastRes7,
        KeyChanges(
            {4: ChangeRecordDelete<int>(), 7: ChangeRecordDelete<int>()}.lock));

    lookups[1].add([1, 2, 0].lock);
    await Future.value();
    expect(lastRes1!.keys, unorderedEquals([0, 1, 2]));
    await Future.value();
    expect(lastRes2, {3: 0}.lock);
    expect(lastRes3, {1: 0}.lock);
    expect(lastRes4, {9: 1, 10: 1}.lock);
    expect(
        lastRes5,
        KeyChanges({1: ChangeRecordDelete<int>(), 10: ChangeRecordDelete<int>()}
            .lock));
    expect(lastRes6, null); // The group just got created
    // Still no changes
    expect(lastRes7, KeyChanges({10: ChangeRecordValue(1)}.lock));

    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
    sub4.cancel();
    sub5.cancel();
    sub6.cancel();
    sub7.cancel();
  });

  test('unsubscribes from group computations correctly', () async {
    final s1 = ValueStream<ChangeEvent<int, int>>(sync: true);
    final sTrap = StreamController
        .broadcast(); // Used for checking if the computation has any listeners left
    final sTrapStream = sTrap.stream;
    final m1 = IComputedMap.fromChangeStream($(() => s1.use));
    final callHistory = <(int, int)>[];
    final m2 = m1.groupByComputed((k, v) => Computed(() {
          callHistory.add((k, v));
          sTrapStream.react((d) => null);
          return v;
        }, assertIdempotent: false));
    final sub = m2.snapshot.listen(null, null);

    s1.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callHistory, [(0, 0)]);
    callHistory.clear();

    s1.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callHistory, [(0, 1)]);
    callHistory.clear();

    s1.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callHistory, []);
    sTrap.add(0);
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callHistory, []);

    s1.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callHistory, [(0, 0)]);
    callHistory.clear();

    s1.add(ChangeEventReplace(<int, int>{}.lock));
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callHistory, []);
    sTrap.add(0);
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callHistory, []);

    s1.add(ChangeEventReplace({0: 1, 1: 2}.lock));
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callHistory, [(0, 1), (1, 2)]);
    callHistory.clear();

    sub.cancel();
    s1.add(ChangeEventReplace({0: 0}.lock));
    sTrap.add(0);
    for (var i = 0; i < 5; i++) await Future.value();
    expect(callHistory, []);
  });

  test('can resubscribe after cancel', () async {
    final s1 = StreamController<ChangeEvent<int, int>>.broadcast(sync: true);
    final s1stream = s1.stream;
    final m1 = IComputedMap.fromChangeStream($(() => s1stream.use));
    final m2 = m1.groupByComputed((k, v) => $(() => v));
    IMap<int, IComputedMap<int, int>>? lastRes1;
    var sub1 = m2.snapshot.listen((event) {
      lastRes1 = event;
    }, null);

    s1.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    await Future.value();
    expect(lastRes1!.keys, [0]);

    sub1.cancel();

    lastRes1 = null;

    sub1 = m2.snapshot.listen((event) {
      lastRes1 = event;
    }, null);

    await Future.value();
    expect(lastRes1!.keys, []);

    s1.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(lastRes1!.keys, [1]);

    sub1.cancel();
  });

  test('elements can lose groups', () async {
    final s1 = StreamController<ChangeEvent<int, int>>.broadcast(sync: true);
    final s1stream = s1.stream;
    final cs = <Computed<int>>[$(() => throw NoValueException()), $(() => 42)];
    final m1 = IComputedMap.fromChangeStream($(() => s1stream.use));
    final m2 = m1.groupByComputed((k, v) => cs[v]);
    IMap<int, IComputedMap<int, int>>? lastRes1;
    var sub1 = m2.snapshot.listen((event) {
      lastRes1 = event;
    }, null);
    IMap<int, int>? lastRes2;
    var sub2 = $(() => m2.snapshot.use[42]?.snapshot.use).listen((event) {
      lastRes2 = event;
    }, null);

    s1.add(KeyChanges({
      0: ChangeRecordValue(1),
      1: ChangeRecordValue(1),
    }.lock));
    await Future.value();
    expect(lastRes1!.keys, [42].lock);
    await Future.value();
    expect(lastRes2, {0: 1, 1: 1}.lock);

    s1.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    await Future.value();
    expect(lastRes1!.keys, [42].lock);
    await Future.value();
    expect(lastRes2, {1: 1}.lock);

    s1.add(KeyChanges({1: ChangeRecordValue(0)}.lock));
    await Future.value();
    expect(lastRes1!.keys, [].lock);
    await Future.value();
    expect(lastRes2, null);

    sub1.cancel();
    sub2.cancel();
  });
}
