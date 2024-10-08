import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('incremental update works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m1 = ComputedMap.fromChangeStream($(() => s.use));
    late (int, int) kv1, kv2;
    final m2 = m1.map((k, v) {
      expect((k, v), kv1);
      return MapEntry(kv2.$1, kv2.$2);
    });
    IMap<int, int>? lastRes;
    final sub = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {}.lock);
    kv1 = (0, 1);
    kv2 = (0, 0);
    s.add(KeyChanges({0: ChangeRecordValue(1)}.lock));
    expect(lastRes, {0: 0}.lock);
    kv1 = (0, 2);
    kv2 = (0, 1);
    s.add(KeyChanges({0: ChangeRecordValue(2)}.lock));
    expect(lastRes, {0: 1}.lock);
    kv1 = (1, 1);
    kv2 = (0, 2);
    s.add(KeyChanges({1: ChangeRecordValue(1)}.lock));
    expect(lastRes, {0: 1}.lock);
    kv1 = (2, 2);
    kv2 = (0, 3);
    s.add(KeyChanges({2: ChangeRecordValue(2)}.lock));
    expect(lastRes, {0: 1}.lock);
    kv1 = (0, 3);
    kv2 = (1, 0);
    s.add(KeyChanges({0: ChangeRecordValue(3)}.lock));
    expect(lastRes, {0: 2, 1: 0}.lock);
    kv1 = (0, 4);
    kv2 = (2, 0);
    s.add(KeyChanges({0: ChangeRecordValue(4)}.lock));
    expect(lastRes, {0: 2, 2: 0}.lock);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes, {0: 2}.lock);
    s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    expect(lastRes, {0: 3}.lock);
    // Duplicate upstream deletion
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes, {0: 3}.lock);
    s.add(KeyChanges({2: ChangeRecordDelete<int>()}.lock));
    expect(lastRes, {}.lock);
    kv1 = (4, 5);
    kv2 = (0, 3);
    s.add(ChangeEventReplace({4: 5}.lock));
    expect(lastRes, {0: 3}.lock);

    sub.cancel();
  });

  test('attributes are coherent', () async {
    final m1 = ComputedMap.fromIMap({0: 1, 1: 2, 2: 3, 3: 4}.lock);

    final m2 = m1.map((k, v) {
      return MapEntry(k % 3, v);
    });

    await testCoherenceInt(m2, {0: 1, 1: 2, 2: 3}.lock);
  });

  test('does not assert idempotency on the user function', () async {
    var cnt = 0;
    final m = ComputedMap.fromIMap({0: 1}.lock)
        .map((key, value) => MapEntry(++cnt, ++cnt));
    expect(await getValue(m.snapshot), {1: 2}.lock);
  });
}
