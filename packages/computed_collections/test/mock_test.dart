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
  final nonExistentKey = expected.keys.reduce(max) + 1;
  final nonExistentValue = expected.values.reduce(max) + 1;

  expect(await getValue(map.snapshot), expected);
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

  expect(await getValue(map.isEmpty), expected.isEmpty);
  expect(await getValue(map.isNotEmpty), expected.isNotEmpty);
  expect(await getValue(map.length), expected.length);
}

Future<void> testFix(IComputedMap<int, int> map) async {
  // A randomly chosen "sentinel" key/value pairs
  // that we assume does not exist in `map`.
  const myKey = 58930586;
  const myValue = 1039572;
  const nonExistentKey = 0;
  const nonExistentValue = 0;
  final myMap = {myKey: myValue}.lock;

  final changes1 = map.changes;
  final snapshot1 = map.snapshot;
  final key1_1 = map[nonExistentKey];
  final key2_1 = map[myKey];
  final containsKey1_1 = map.containsKey(nonExistentKey);
  final containsKey2_1 = map.containsKey(myKey);
  final containsValue1_1 = map.containsValue(nonExistentValue);
  final containsValue2_1 = map.containsValue(myValue);
  final isEmpty1 = map.isEmpty;
  final isNotEmpty1 = map.isNotEmpty;
  final length1 = map.length;

  map.fix(myMap);

  final changes2 = map.changes;
  final snapshot2 = map.snapshot;
  final key1_2 = map[nonExistentKey];
  final key2_2 = map[myKey];
  final containsKey1_2 = map.containsKey(nonExistentKey);
  final containsKey2_2 = map.containsKey(myKey);
  final containsValue1_2 = map.containsValue(nonExistentValue);
  final containsValue2_2 = map.containsValue(myValue);
  final isEmpty2 = map.isEmpty;
  final isNotEmpty2 = map.isNotEmpty;
  final length2 = map.length;

  expect(await getValue(changes1), ChangeEventReplace(myMap));
  expect(await getValue(changes2), ChangeEventReplace(myMap));

  expect(await getValue(snapshot1), myMap);
  expect(await getValue(snapshot2), myMap);

  expect(await getValue(key1_1), null);
  expect(await getValue(key1_2), null);

  expect(await getValue(key2_1), myValue);
  expect(await getValue(key2_2), myValue);

  expect(await getValue(containsKey1_1), false);
  expect(await getValue(containsKey1_2), false);

  expect(await getValue(containsKey2_1), true);
  expect(await getValue(containsKey2_2), true);

  expect(await getValue(containsValue1_1), false);
  expect(await getValue(containsValue1_2), false);

  expect(await getValue(containsValue2_1), true);
  expect(await getValue(containsValue2_2), true);

  expect(await getValue(isEmpty1), false);
  expect(await getValue(isEmpty2), false);

  expect(await getValue(isNotEmpty1), true);
  expect(await getValue(isNotEmpty2), true);

  expect(await getValue(length1), 1);
  expect(await getValue(length2), 1);

  // Mock to an empty map
  map.fix(<int, int>{}.lock);

  expect(await getValue(changes1), ChangeEventReplace({}.lock));
  expect(await getValue(snapshot1), {}.lock);
  expect(await getValue(key1_1), null);
  expect(await getValue(key2_1), null);
  expect(await getValue(containsKey1_1), false);
  expect(await getValue(containsKey2_1), false);
  expect(await getValue(containsValue1_1), false);
  expect(await getValue(containsValue2_1), false);
  expect(await getValue(isEmpty1), true);
  expect(await getValue(isNotEmpty1), false);
  expect(await getValue(length1), 0);

  map.unmock();

  // The sentinel key/values should disappear

  expect(await getValue(key2_1), null);
  expect(await getValue(key2_2), null);

  expect(await getValue(containsKey2_1), false);
  expect(await getValue(containsKey2_2), false);

  expect(await getValue(containsValue2_1), false);
  expect(await getValue(containsValue2_2), false);
}

void main() {
  test('add', () async {
    // We use a `ValueStream` here instead of a raw `StreamController`
    // so that the maps can re-subscribe to it
    final cs = ValueStream.seeded(ChangeEventReplace({0: 1}.lock));
    final m = IComputedMap.fromChangeStream(cs);
    final a = m.add(1, 2);
    await testFix(a);
    await testCoherence(a, {0: 1, 1: 2}.lock);
  });
}
