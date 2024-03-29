import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

Future<void> expectValue<T>(Computed<T> c, T value) async {
  var flag = false;
  final sub = c.listen((event) {
    expect(flag, false);
    expect(event, value);
    flag = true;
  }, null);
  await Future.value();
  expect(flag, true);
  for (var i = 0; i < 5; i++) {
    // Wait for several microtasks to make sure the value does not change
    await Future.value();
  }
  sub.cancel();
}

Future<void> testFixUnmock(IComputedMap<int, int> map) async {
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

  await expectValue(changes1, ChangeEventReplace(myMap));
  await expectValue(changes2, ChangeEventReplace(myMap));

  await expectValue(snapshot1, myMap);
  await expectValue(snapshot2, myMap);

  await expectValue(key1_1, null);
  await expectValue(key1_2, null);

  await expectValue(key2_1, myValue);
  await expectValue(key2_2, myValue);

  await expectValue(containsKey1_1, false);
  await expectValue(containsKey1_2, false);

  await expectValue(containsKey2_1, true);
  await expectValue(containsKey2_2, true);

  await expectValue(containsValue1_1, false);
  await expectValue(containsValue1_2, false);

  await expectValue(containsValue2_1, true);
  await expectValue(containsValue2_2, true);

  await expectValue(isEmpty1, false);
  await expectValue(isEmpty2, false);

  await expectValue(isNotEmpty1, true);
  await expectValue(isNotEmpty2, true);

  await expectValue(length1, 1);
  await expectValue(length2, 1);

  // TODO: mock to an empty map

  // TODO: remember the original values, unmock, make sure it turns back
}

void main() {
  test('add', () async {
    final m = IComputedMap.fromChangeStream(
        Stream.value(ChangeEventReplace({0: 1}.lock)));
    await testFixUnmock(m.add(1, 2));
  });
}
