import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('incremental update works', () async {
    final s1 = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream($(() => s1.use));
    // Make different elements depend on different data sources, because why not
    final lookups =
        List.generate(2, (_) => ValueStream<IList<int>>(sync: true));
    final m2 =
        m1.mapComputed((k, v) => $(() => Entry(lookups[k % 3].use[v % 3], v)));
    IMap<int, int>? snapshot;
    final sub1 = m2.snapshot.listen((event) {
      snapshot = event;
    }, null);
    ChangeEvent<int, int>? change;
    final sub8 = m2.changes.listen((event) {
      change = event;
    }, null);
    await Future.value();
    expect(snapshot, {}.lock);
    for (var i = 0; i < 5; i++) {
      await Future.value();
    }
    expect(change, null);

    s1.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    // This by itself causes no change on the collection, as the entry computation has no value yet
    for (var i = 0; i < 5; i++) {
      await Future.value();
    }
    expect(snapshot, {}.lock);
    expect(change, null);

    // This adds a new key
    lookups[0].add([0, 1, 2].lock);
    await Future.value();
    expect(snapshot, {1: 1}.lock);
    expect(change, KeyChanges({1: ChangeRecordValue(1)}.lock));

    // Change the key of an existing item, removing a key
    // + add a new key
    lookups[0].add([1, 2, 2].lock);
    await Future.value();
    await Future.value();
    expect(snapshot!, {2: 1}.lock);
    expect(
        change,
        KeyChanges(
            {1: ChangeRecordDelete<int>(), 2: ChangeRecordValue(1)}.lock));

    // Change the value of an existing item, while preserving its key
    s1.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    await Future.value();
    await Future.value();
    expect(snapshot, {2: 2}.lock);
    expect(change, KeyChanges({2: ChangeRecordValue(2)}.lock));

    // Remove a key by removing the only entry in it
    // And add a new element upstream, creating a new key
    lookups[1].add([0, 0, 2].lock);
    s1.add(KeyChanges(
        {0: ChangeRecordDelete<int>(), 1: ChangeRecordValue(1)}.lock));
    await Future.value();
    await Future.value();
    expect(snapshot, {0: 1}.lock);
    expect(
        change,
        KeyChanges({
          0: ChangeRecordValue(1),
          2: ChangeRecordDelete<int>(),
        }.lock));

    // Add new entries to an existing key
    s1.add(KeyChanges({4: ChangeRecordValue(0), 7: ChangeRecordValue(3)}.lock));
    await Future.value();
    await Future.value();
    // Note that the new entry takes priority
    expect(snapshot, {0: 3}.lock);
    expect(
        change,
        KeyChanges({
          0: ChangeRecordValue(3),
        }.lock));

    // Remove an entry from an existing key, which has other entries,
    //  triggering a change in value.
    s1.add(KeyChanges({7: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    await Future.value();
    expect(snapshot!, {0: 0}.lock);
    expect(
        change,
        KeyChanges({
          0: ChangeRecordValue(0),
        }.lock));

    // Remove an entry from an existing key, which has other entries,
    //  without triggering a change in value.
    s1.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    await Future.value();
    expect(snapshot!, {0: 0}.lock);
    expect(
        change,
        KeyChanges({
          0: ChangeRecordValue(0),
        }.lock)); // No change

    // Upstream replacement
    s1.add(ChangeEventReplace({0: 0, 1: 1, 3: 2, 4: 0}.lock));
    await Future.value();
    expect(snapshot, {0: 0, 1: 0, 2: 2}.lock);
    expect(change, ChangeEventReplace({0: 0, 1: 0, 2: 2}.lock));

    // Change the mapped key of a non-leader entry
    s1.add(KeyChanges({1: ChangeRecordValue(5)}.lock));
    await Future.value();
    await Future.value();
    expect(snapshot, {0: 0, 1: 0, 2: 5}.lock);
    expect(
        change,
        KeyChanges({
          2: ChangeRecordValue(5),
        }.lock));

    // Change the mapped key of a leader entry, while keeping its former key populated
    s1.add(KeyChanges({1: ChangeRecordValue(1)}.lock));
    await Future.value();
    await Future.value();
    expect(snapshot, {0: 1, 1: 0, 2: 2}.lock);
    expect(
        change,
        KeyChanges({
          0: ChangeRecordValue(1),
          2: ChangeRecordValue(2),
        }.lock));

    // Delete an upstream key, removing a key, but a new entry immediately re-creates it
    s1.add(KeyChanges(
        {3: ChangeRecordDelete<int>(), 6: ChangeRecordValue(5)}.lock));
    await Future.value();
    await Future.value();
    expect(snapshot, {0: 1, 1: 0, 2: 5}.lock);
    expect(change, KeyChanges({2: ChangeRecordValue(5)}.lock));

    // Make multiple changes to groups in one upstream change
    s1.add(KeyChanges({
      1: ChangeRecordValue(2),
      3: ChangeRecordValue(3),
      4: ChangeRecordDelete<int>(),
      6: ChangeRecordDelete<int>(),
      7: ChangeRecordValue(2),
      9: ChangeRecordValue(1)
    }.lock));
    await Future.value();
    await Future.value();
    expect(snapshot, {1: 3, 2: 1}.lock);
    expect(
        change,
        KeyChanges({
          0: ChangeRecordDelete<int>(),
          1: ChangeRecordValue(3),
          2: ChangeRecordValue(1)
        }.lock));

    // Change the mapping
    lookups[0].add([0, 1, 2].lock);
    await Future.value();
    expect(snapshot, {0: 3, 1: 1, 2: 2}.lock);
    expect(
        change,
        KeyChanges({
          0: ChangeRecordValue(3),
          1: ChangeRecordValue(1),
          2: ChangeRecordValue(2)
        }.lock));

    sub1.cancel();
    sub8.cancel();
  });

  test('unsubscribes from entry computations correctly', () async {
    final s1 = ValueStream<ChangeEvent<int, int>>(sync: true);
    final sTrap = StreamController
        .broadcast(); // Used for checking if the computation has any listeners left
    final sTrapStream = sTrap.stream;
    final m1 = IComputedMap.fromChangeStream($(() => s1.use));
    final callHistory = <(int, int)>[];
    final m2 = m1.mapComputed((k, v) => Computed(() {
          callHistory.add((k, v));
          sTrapStream.react((d) => null);
          return Entry(k, v);
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
    final m2 = m1.mapComputed((k, v) => $(() => Entry(k, v)));
    IMap<int, int>? lastRes1;
    var sub = m2.snapshot.listen((event) {
      lastRes1 = event;
    }, null);

    s1.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    await Future.value();
    await Future.value();
    expect(lastRes1, {0: 0}.lock);

    sub.cancel();

    lastRes1 = null;

    sub = m2.snapshot.listen((event) {
      lastRes1 = event;
    }, null);

    await Future.value();
    expect(lastRes1, {}.lock);

    s1.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    await Future.value();
    await Future.value();
    expect(lastRes1!, {0: 1}.lock);

    sub.cancel();
  });

  test('upstream elements can lose entries', () async {
    final s1 = StreamController<ChangeEvent<int, int>>.broadcast(sync: true);
    final s1stream = s1.stream;
    final cs = <Computed<Entry<int, int>> Function(int)>[
      (_) => $(() => throw NoValueException()),
      (k) => $(() => Entry(42, k))
    ];
    final m1 = IComputedMap.fromChangeStream($(() => s1stream.use));
    final m2 = m1.mapComputed((k, v) => cs[v](k));
    IMap<int, int>? snapshot;
    final sub = m2.snapshot.listen((event) {
      snapshot = event;
    }, null);

    s1.add(KeyChanges({
      0: ChangeRecordValue(1),
      1: ChangeRecordValue(1),
    }.lock));
    await Future.value();
    await Future.value();
    expect(snapshot, {42: 1}.lock);

    s1.add(KeyChanges({1: ChangeRecordValue(0)}.lock));
    await Future.value();
    await Future.value();
    expect(snapshot, {42: 0}.lock);

    s1.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    await Future.value();
    await Future.value();
    expect(snapshot, {}.lock);

    sub.cancel();
  });

  test('attributes are coherent', () async {
    final m1 = IComputedMap({0: 1, 1: 2, 2: 3, 3: 4}.lock);

    final m2 = m1.mapComputed((k, v) {
      return $(() => Entry(k % 3, v));
    });

    await testCoherenceInt(m2, {1: 2, 2: 3, 0: 4}.lock);
  });
}
