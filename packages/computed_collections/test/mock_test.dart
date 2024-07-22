import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/cs_computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<void> testFixUnmock_(
    IComputedMap<int, int> map, bool trackChangeStream) async {
  // A randomly chosen "sentinel" key/value pairs
  // that we assume does not exist in `map`.
  const myKey = 58930586;
  const myValue = 1039572;
  const nonExistentKey = 0;
  const nonExistentValue = 0;
  final myMap = {myKey: myValue}.lock;

  final original = (await getValues(map.snapshot)).last;

  // Unlike `testCoherence`, these test that computations created before fixing
  // the map also behave properly
  final cscm = IComputedMap.fromChangeStream(map.changes);
  ComputedSubscription? sub;
  if (trackChangeStream) {
    sub = cscm.snapshot.listen(null,
        null); // Make sure the cscm has listeners throughout the mock/unmock cycle
  }
  try {
    /*final snapshot = map.snapshot;
    final key1 = map[nonExistentKey];
    final key2 = map[myKey];
    final containsKey1 = map.containsKey(nonExistentKey);
    final containsKey2 = map.containsKey(myKey);
    final containsValue1 = map.containsValue(nonExistentValue);
    final containsValue2 = map.containsValue(myValue);
    final isEmpty = map.isEmpty;
    final isNotEmpty = map.isNotEmpty;
    final length = map.length;*/

    map.fix(myMap);
    /*await testCoherenceInt(map, myMap);
    if (trackChangeStream) {
      // The change stream should also be consistent, evidenced by the coherence of the cscm tracking the change strean
      await testCoherenceInt(cscm, myMap);
    }

    expect(await getValue(snapshot), myMap);
    expect(await getValue(key1), null);
    expect(await getValue(key2), myValue);
    expect(await getValue(containsKey1), false);
    expect(await getValue(containsKey2), true);
    expect(await getValue(containsValue1), false);
    expect(await getValue(containsValue2), true);
    expect(await getValue(isEmpty), false);
    expect(await getValue(isNotEmpty), true);
    expect(await getValue(length), 1);

    // Mock to an empty map
    map.fix(<int, int>{}.lock);
    await testCoherenceInt(map, <int, int>{}.lock);
    if (trackChangeStream) {
      await testCoherenceInt(cscm, <int, int>{}.lock);
    }

    expect(await getValue(snapshot), {}.lock);
    expect(await getValue(key1), null);
    expect(await getValue(key2), null);
    expect(await getValue(containsKey1), false);
    expect(await getValue(containsKey2), false);
    expect(await getValue(containsValue1), false);
    expect(await getValue(containsValue2), false);
    expect(await getValue(isEmpty), true);
    expect(await getValue(isNotEmpty), false);
    expect(await getValue(length), 0);

    map.fix(myMap);
    await testCoherenceInt(map, myMap);
    if (trackChangeStream) {
      await testCoherenceInt(cscm, myMap);
    }*/

    map.unmock();
    await testCoherenceInt(map, original);
    if (trackChangeStream) {
      await testCoherenceInt(cscm, original);
    }
  } finally {
    sub?.cancel();
  }
}

Future<void> testFixUnmock(IComputedMap<int, int> map) async {
  // Test both with and without there being a listener present on the .change stream during the mock/unmock cycle
  //await testFixUnmock_(map, false);
  await testFixUnmock_(map, true);
}

// Test that the replacement change stream is consistent across
// mocks/unmocks and delegates the mocked change stream
Future<void> _testMock1(IComputedMap<int, int> map) async {
  final s = StreamController.broadcast(sync: true);
  final stream = s.stream;
  // Track the change stream of the given map
  final cscm = IComputedMap.fromChangeStream(map.changes);
  final sub = cscm.snapshot
      .listen(null, null); // Make sure the cscm has listeners throughout
  try {
    final snapshotBefore = await getValue(map.snapshot);
    map.mock(IComputedMap.fromChangeStream($(() => stream.use)));
    try {
      expect(await getValue(cscm.snapshot), {}.lock);
      s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
      // If the cscm receives the correct value, map.changes must be propagating the mocked change stream
      expect(await getValue(cscm.snapshot), {0: 1}.lock);
      // Make it propagate another change just for good measure
      s.add(ChangeEventReplace({1: 2}.lock));
      expect(await getValue(cscm.snapshot), {1: 2}.lock);
    } finally {
      map.unmock();
    }
    // After unmocking, the value of the tracking cscm must be replaced with
    // the snapshot of the collection before the mock
    expect(await getValue(cscm.snapshot), snapshotBefore);
  } finally {
    sub.cancel();
  }
}

// Test that the replacement stream works even after being cancelled and re-listened
Future<void> _testMock2(IComputedMap<int, int> map) async {
  final cscm = IComputedMap.fromChangeStream(map.changes);
  var sub1 = cscm.snapshot.listen(null, null);
  try {
    final initialValueStream = ValueStream<IMap<int, int>>(sync: true);
    final cs = StreamController<ChangeEvent<int, int>>.broadcast(sync: true);
    final changeStream = cs.stream;
    map.mock(ChangeStreamComputedMap($(() => changeStream.use),
        initialValueComputer: () => initialValueStream.use));
    try {
      sub1.cancel();
      initialValueStream.add(<int, int>{1: 2}.lock);
      sub1 = cscm.snapshot.listen(null, null);
      // This may be empty - as cscm is merely tracking the change stream of the given map
      // and not looking at its snapshot, and the value of the mocked collection did not
      // actually change since the listener was added.
      // SnapshotStreamComputedMap still emits a replacement event, though
      expect(
          await getValue(cscm.snapshot),
          anyOf([
            {}.lock,
            {1: 2}.lock
          ]));
      // Make it propagate a change
      cs.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
      expect(
          await getValue(cscm.snapshot),
          anyOf([
            {0: 1}.lock,
            {0: 1, 1: 2}.lock
          ]));
      // Make it propagate another change for good measure
      cs.add(ChangeEventReplace({1: 2}.lock));
      expect(await getValue(cscm.snapshot), {1: 2}.lock);
    } finally {
      map.unmock();
    }
  } finally {
    sub1.cancel();
  }
}

Future<void> testMock(IComputedMap<int, int> map) async {
  await _testMock1(map);
  await _testMock2(map);
}

void main() {
  test('fromChangeStream', () async {
    final s = ValueStream<ChangeEvent<int, int>>.seeded(
        ChangeEventReplace({1: 2}.lock));
    final m = IComputedMap.fromChangeStream($(() => s.use));
    await testFixUnmock(m);
    await testMock(m);
    expect(await getValuesWhile(m.changes, () => m.fix({2: 3}.lock)), [
      ChangeEventReplace({2: 3}.lock)
    ]);
  });
  test('fromSnapshotStream', () async {
    final m = IComputedMap.fromSnapshotStream($(() => {0: 1}.lock));
    await testFixUnmock(m);
    await testMock(m);
    expect(await getValuesWhile(m.changes, () => m.fix({2: 3}.lock)), [
      KeyChanges({0: ChangeRecordDelete<int>(), 2: ChangeRecordValue(3)}.lock)
    ]);
  });
  test('add', () async {
    final m = IComputedMap({0: 1}.lock);
    final a = m.add(1, 2);
    await testFixUnmock(a);
    await testMock(a);
    expect(await getValuesWhile(a.changes, () => m.fix({2: 3}.lock)), [
      ChangeEventReplace({1: 2, 2: 3}.lock)
    ]);
  });
  test('mapValues', () async {
    final m = IComputedMap({0: 1}.lock);
    final mv = m.mapValues((key, value) => value + 1);
    await testFixUnmock(mv);
    await testMock(mv);
    expect(await getValuesWhile(mv.changes, () => m.fix({2: 3}.lock)), [
      ChangeEventReplace({2: 4}.lock)
    ]);
  });
  test('mapValuesComputed', () async {
    final m = IComputedMap({0: 1}.lock);
    final mv = m.mapValuesComputed((key, value) => $(() => value + 1));
    await testFixUnmock(mv);
    await testMock(mv);
    expect(await getValuesWhile(mv.changes, () => m.fix({2: 3}.lock)), [
      ChangeEventReplace({2: 4}.lock)
    ]);
  });
  test('const', () async {
    final c = IComputedMap({0: 1}.lock);
    await testFixUnmock(c);
    await testMock(c);
    expect(await getValues(c.changes), []);
  });

  test('map', () async {
    final m = IComputedMap({0: 1}.lock);
    final mv = m.map((key, value) => MapEntry(key, value));
    await testFixUnmock(mv);
    await testMock(mv);
    expect(await getValuesWhile(mv.changes, () => m.fix({2: 3}.lock)), [
      ChangeEventReplace({2: 3}.lock)
    ]);
  });
}
