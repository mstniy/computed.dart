import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:test/test.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';

import 'helpers.dart';

void main() {
  test('change stream works', () async {
    final s = ValueStream<ChangeEvent<int, ComputedMap<int, int>>>(sync: true);
    final m = ComputedMap.fromChangeStream($(() => s.use)).flat();

    var cnt = 0;
    ChangeEvent<(int, int), int>? last;
    final sub = m.changes.listen((c) {
      cnt++;
      last = c;
    });

    await Future.value();
    await Future.value();
    expect(cnt, 0);

    final stream0 = ValueStream<ChangeEvent<int, int>>(sync: true);
    final nested0 = ComputedMap.fromChangeStream($(() => stream0.use));

    expect(stream0.hasListener, false);

    s.add(KeyChanges({0: ChangeRecordValue(nested0)}.lock));
    expect(stream0.hasListener, true);
    await Future.value();
    expect(cnt, 0);

    stream0.add(
        KeyChanges({1: ChangeRecordValue(2), 3: ChangeRecordValue(4)}.lock));
    await Future.value();
    expect(cnt, 1);
    expect(
        last,
        KeyChanges(
            {(0, 1): ChangeRecordValue(2), (0, 3): ChangeRecordValue(4)}.lock));

    stream0.add(KeyChanges(
        {1: ChangeRecordValue(3), 3: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(cnt, 2);
    expect(
        last,
        KeyChanges({
          (0, 1): ChangeRecordValue(3),
          (0, 3): ChangeRecordDelete<int>()
        }.lock));

    stream0.add(ChangeEventReplace({5: 6}.lock));
    await Future.value();
    expect(cnt, 3);
    expect(
        last,
        KeyChanges({
          (0, 1): ChangeRecordDelete<int>(),
          (0, 5): ChangeRecordValue(6),
        }.lock));

    s.add(KeyChanges({0: ChangeRecordDelete<ComputedMap<int, int>>()}.lock));
    expect(stream0.hasListener, false);
    await Future.value();
    expect(cnt, 4);
    expect(
        last,
        KeyChanges({
          (0, 5): ChangeRecordDelete(),
        }.lock));

    s.add(ChangeEventReplace({
      0: nested0,
      1: ComputedMap.fromIMap({2: 3}.lock)
    }.lock));
    await Future.value();
    expect(cnt, 5);
    expect(
        last,
        ChangeEventReplace({
          (1, 2): 3,
        }.lock));
    // Takes another MT for Computed to subscribe to nested0 again
    await Future.value();
    expect(cnt, 6);
    expect(
        last,
        KeyChanges({
          (0, 5): ChangeRecordValue(6),
        }.lock));

    s.add(ChangeEventReplace({
      2: ComputedMap.fromIMap({4: 5}.lock),
    }.lock));
    await Future.value();
    expect(cnt, 7);
    expect(
        last,
        ChangeEventReplace({
          (2, 4): 5,
        }.lock));

    s.add(KeyChanges({
      2: ChangeRecordValue(ComputedMap.fromIMap({6: 7}.lock)),
    }.lock));
    await Future.value();
    expect(cnt, 8);
    expect(
        last,
        KeyChanges({
          (2, 4): ChangeRecordDelete<int>(),
          (2, 6): ChangeRecordValue(7),
        }.lock));

    sub.cancel();
  });

  test('attributes are coherent', () async {
    final m1 = ComputedMap.fromIMap({
      0: ComputedMap.fromIMap({1: 2}.lock),
      3: ComputedMap.fromIMap({4: 5, 6: 7}.lock)
    }.lock);
    final m2 = m1.flat();
    await testCoherence(m2, {(0, 1): 2, (3, 4): 5, (3, 6): 7}.lock, (0, 0), 0);
  });
}
