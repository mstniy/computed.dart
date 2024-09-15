import 'dart:async';
import 'dart:math';

import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/expect.dart';

Future<List<T>> getValuesWhile<T>(
    Computed<T> c, FutureOr<void> Function() f) async {
  final values = <T>[];
  Object? exc;
  final sub = c.listen((event) {
    values.add(event);
  }, (e) => exc = e);
  await f();
  for (var i = 0; i < 5; i++) {
    // Wait for several microtasks to make sure the value assumes its value
    await Future.value();
  }
  sub.cancel();
  if (exc != null) throw exc!;

  return values;
}

Future<List<T>> getValues<T>(Computed<T> c) => getValuesWhile(c, () {});

Future<T> getValue<T>(Computed<T> c) async {
  final values = await getValues(c);
  expect(values.length, 1);
  return values.first;
}

Future<void> testCoherenceInt(
    ComputedMap<int, int> map, IMap<int, int> expected) async {
  final nonExistentKey = expected.isEmpty ? 0 : expected.keys.reduce(max) + 1;
  final nonExistentValue =
      expected.isEmpty ? 0 : expected.values.reduce(max) + 1;
  return testCoherence(map, expected, nonExistentKey, nonExistentValue);
}

Future<void> testCoherence<K, V>(ComputedMap<K, V> map, IMap<K, V> expected,
    K nonExistentKey, V nonExistentValue) async {
  // Test them twice for good measure
  for (var i = 0; i < 2; i++) {
    expect(await getValues(map.snapshot),
        anyOf(equals([expected]), [{}.lock, expected]));
    expect(await getValue(map[nonExistentKey]), null);
    for (var e in expected.entries) {
      expect(await getValues(map[e.key]),
          anyOf(equals([null, e.value]), [e.value]));
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
}

Future<void> testExceptions(
    ComputedMap<int, int> map, EventSink<ChangeEvent<int, int>> s) async {
  for (final x in [
    () => map.snapshot,
    () => map.changes,
    () => map[0],
    () => map.isEmpty,
    () => map.isNotEmpty,
    () => map.length,
    () => map.containsKey(0),
    () => map.containsValue(0),
  ]) {
    var cnt = 0;
    Object? last;
    final sub = x().listen(null, (e) {
      cnt++;
      last = e;
    });

    await Future.value();
    s.addError(42);
    await Future.value(); // In case the given map has a MT delay
    expect(cnt, 1);
    expect(last, 42);

    sub.cancel();
  }
}
