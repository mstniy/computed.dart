import 'dart:math';

import 'package:computed/computed.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/expect.dart';

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
