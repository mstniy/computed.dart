import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  test('incremental update works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = IComputedMap.fromChangeStream(s);
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
    await Future.value();
    expect(lastRes1, {}.lock);
    await Future.value();
    await Future.value();
    expect(lastRes2, null);
    expect(lastRes3, null);
    expect(lastRes4, null);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock)); // Add a new group
    await Future.value();
    expect(lastRes1!.keys, [1]);
    await Future.value();
    expect(lastRes2, null);
    expect(lastRes3, {0: 1}.lock);
    expect(lastRes4, null);
    // Change the value of an existing item, removing a group
    // + add a new group
    s.add(KeyChanges({0: ChangeRecordValue(2), 1: ChangeRecordValue(0)}.lock));
    await Future.value();
    expect(lastRes1!.keys, containsAll([0, 2]));
    await Future.value(); // TODO: can we get rid of this extra lag?
    expect(lastRes2, {1: 0}.lock);
    expect(lastRes3, null);
    expect(lastRes4, {0: 2}.lock);
    // Change the value of an existing item, while preserving its group
    // + Remove a group by removing an item
    s.add(KeyChanges(
        {0: ChangeRecordDelete<int>(), 1: ChangeRecordValue(3)}.lock));
    await Future.value();
    expect(lastRes1!.keys, containsAll([0]));
    await Future.value();
    expect(lastRes2, {1: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    // Add a value to an existing group
    s.add(KeyChanges({0: ChangeRecordValue(0)}.lock));
    await Future.value();
    expect(lastRes1!.keys, containsAll([0]));
    await Future.value();
    expect(lastRes2, {0: 0, 1: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    // Remove a value from an existing group, which has other elements
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(lastRes1!.keys, containsAll([0]));
    await Future.value();
    expect(lastRes2, {1: 3}.lock);
    expect(lastRes3, null);
    expect(lastRes4, null);
    // Upstream replacement
    s.add(ChangeEventReplace({0: 0, 1: 1, 2: 3}.lock));
    await Future.value();
    expect(lastRes1!.keys, containsAll([0, 1]));
    await Future.value();
    expect(lastRes2, {0: 0, 2: 3}.lock);
    expect(lastRes3, {1: 1}.lock);
    expect(lastRes4, null);
    // Change the group of an item, changing its group, but keeping its former group populated
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    await Future.value();
    expect(lastRes1!.keys, containsAll([0, 1]));
    await Future.value();
    expect(lastRes2, {2: 3}.lock);
    expect(lastRes3, {0: 1, 1: 1}.lock);
    expect(lastRes4, null);
    // Delete a key, removing a group, but a new key immediately re-creates it
    s.add(KeyChanges(
        {0: ChangeRecordValue(3), 2: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(lastRes1!.keys, containsAll([0, 1]));
    await Future.value();
    expect(lastRes2, {0: 3}.lock);
    expect(lastRes3, {1: 1}.lock);
    expect(lastRes4, null);

    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
    sub4.cancel();
  });

  test('initial computation works', () async {});
  test('operator[] works', () async {});

  test('mock works', () async {});
}
