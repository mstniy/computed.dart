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
    final snapshot = map.snapshot;
    final key1 = map[nonExistentKey];
    final key2 = map[myKey];
    final containsKey1 = map.containsKey(nonExistentKey);
    final containsKey2 = map.containsKey(myKey);
    final containsValue1 = map.containsValue(nonExistentValue);
    final containsValue2 = map.containsValue(myValue);
    final isEmpty = map.isEmpty;
    final isNotEmpty = map.isNotEmpty;
    final length = map.length;

    map.fix(myMap);
    await testCoherence(map, myMap);
    if (trackChangeStream) {
      // The change stream should also be consistent, evidenced by the coherence of the cscm tracking the change strean
      await testCoherence(cscm, myMap);
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
    await testCoherence(map, <int, int>{}.lock);
    if (trackChangeStream) {
      await testCoherence(cscm, <int, int>{}.lock);
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
    await testCoherence(map, myMap);
    if (trackChangeStream) {
      await testCoherence(cscm, myMap);
    }

    map.unmock();
    await testCoherence(map, original);
    if (trackChangeStream) {
      await testCoherence(cscm, original);
    }
  } finally {
    sub?.cancel();
  }
}

Future<void> testFixUnmock(IComputedMap<int, int> map) async {
  // Test both with and without there being a listener present on the .change stream during the mock/unmock cycle
  await testFixUnmock_(map, false);
  await testFixUnmock_(map, true);
}

// Test that the replacement change stream starts with a replacement event
// and delegates the mocked change stream thereafter
Future<void> _testMock1(IComputedMap<int, int> map) async {
  final s = StreamController.broadcast(sync: true);
  final stream = s.stream;
  final changes1 = map.changes;
  final buffer1 = <ChangeEvent<int, int>>[];
  final sub1 = changes1.listen(buffer1.add, null);
  try {
    map.mock(IComputedMap.fromChangeStream($(() => stream.use)));
    try {
      final changes2 = map.changes;
      final buffer2 = <ChangeEvent<int, int>>[];
      final sub2 = changes2.listen(buffer2.add, null);
      try {
        expect(buffer1, [ChangeEventReplace({}.lock)]);
        expect(buffer2, []);
        buffer1.clear();
        buffer2.clear();
        final change = KeyChanges({0: ChangeRecordValue(1)}.lock);
        s.add(change);
        expect(buffer1, [change]);
        expect(buffer2, [change]);
      } finally {
        sub2.cancel();
      }
    } finally {
      map.unmock();
    }
  } finally {
    sub1.cancel();
  }
}

// Test that the replacement stream is voided once cancelled
Future<void> _testMock2(IComputedMap<int, int> map) async {
  final changes1 = map.changes;
  final buffer1 = <ChangeEvent<int, int>>[];
  var sub1 = changes1.listen(buffer1.add, null);
  try {
    final initialValueStream = ValueStream<IMap<int, int>>(sync: true);
    map.mock(ChangeStreamComputedMap(
        $(() => throw NoValueException()), () => initialValueStream.use));
    try {
      sub1.cancel();
      initialValueStream.add(<int, int>{}.lock);
      sub1 = changes1.listen(buffer1.add, null);
      await Future.value();
      expect(buffer1, []); // And not a replacement event
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
}
