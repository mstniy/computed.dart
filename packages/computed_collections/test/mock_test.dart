import 'dart:math';

import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

Future<List<T>> getValues<T>(Computed<T> c) async {
  final values = <T>[];
  final sub = c.listen((event) {
    values.add(event);
  }, null);
  for (var i = 0; i < 5; i++) {
    // Wait for several microtasks to make sure the value assumes its value
    await Future.value();
  }
  sub.cancel();

  return values;
}

Future<T> getValue<T>(Computed<T> c) async {
  final values = await getValues(c);
  expect(values.length, 1);
  return values.first;
}

Future<void> testCoherence(
    IComputedMap<int, int> map, IMap<int, int> expected) async {
  final nonExistentKey = expected.isEmpty ? 0 : expected.keys.reduce(max) + 1;
  final nonExistentValue =
      expected.isEmpty ? 0 : expected.values.reduce(max) + 1;

  expect(await getValues(map.snapshot),
      anyOf(equals([expected]), [{}.lock, expected]));
  expect(await getValue(map[nonExistentKey]), null);
  for (var e in expected.entries) {
    expect(
        await getValues(map[e.key]), anyOf(equals([null, e.value]), [e.value]));
    expect(await getValues(map.containsKey(e.key)),
        anyOf(equals([false, true]), [true]));
    expect(await getValues(map.containsValue(e.value)),
        anyOf(equals([false, true]), [true]));
  }
  expect(await getValue(map.containsKey(nonExistentKey)), false);

  expect(await getValue(map.containsValue(nonExistentValue)), false);

  expect(await getValues(map.isEmpty),
      anyOf(equals([true, expected.isEmpty]), [expected.isEmpty]));
  expect(await getValues(map.isNotEmpty),
      anyOf(equals([false, expected.isNotEmpty]), [expected.isNotEmpty]));
  expect(await getValues(map.length),
      anyOf(equals([0, expected.length]), [expected.length]));
}

Future<void> testFixUnmock(IComputedMap<int, int> map) async {
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
  final changes = map.changes;
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

  expect(await getValue(changes), ChangeEventReplace(myMap));
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

  expect(await getValue(changes), ChangeEventReplace({}.lock));
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

  map.unmock();

  await testCoherence(map, original);
}

void main() {
  // We use a `ValueStream` here instead of a raw `StreamController`
  // so that the maps can re-subscribe to it
  final cs = ValueStream.seeded(ChangeEventReplace({0: 1}.lock));
  final m = IComputedMap.fromChangeStream(cs);
  test('add', () async {
    final a = m.add(1, 2);
    await testFixUnmock(a);
  });
  test('mapValues', () async {
    final mv = m.mapValues((key, value) => value + 1);
    await testFixUnmock(mv);
  });
  test('mapValuesComputed', () async {
    final mv = m.mapValuesComputed((key, value) => $(() => value + 1));
    await testFixUnmock(mv);
  });
}