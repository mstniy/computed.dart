import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  test('works without any upstream changes', () async {
    for (var e in [
      ((CSTracker<int, int> t) => t[0], 1),
      ((CSTracker<int, int> t) => t[1], null),
      ((CSTracker<int, int> t) => t.containsKey(0), true),
      ((CSTracker<int, int> t) => t.containsKey(1), false),
      ((CSTracker<int, int> t) => t.containsValue(0), false),
      ((CSTracker<int, int> t) => t.containsValue(1), true)
    ]) {
      final ss = ValueStream<IMap<int, int>>(sync: true);
      final tracker =
          CSTracker($(() => throw NoValueException()), $(() => ss.use));
      Object? res;
      final sub = e.$1(tracker).listen((e) => res = e);
      ss.add({0: 1}.lock);
      expect(res, e.$2);
      sub.cancel();
    }
  });
  test('upstream replacements work', () async {
    final cs = StreamController<ChangeEvent<int, int>>.broadcast(sync: true);
    final changes = cs.stream;
    final changesComputed = $(() => changes.use);
    final ss = snapshotComputation(changesComputed, () => <int, int>{}.lock);
    final tracker = CSTracker(changesComputed, ss);
    final cnts = List.generate(5, (index) => 0);
    final last = List<int?>.generate(5, (index) => null);
    final subs = List.generate(
        5,
        (idx) => tracker[idx].listen((event) {
              cnts[idx]++;
              last[idx] = event;
            }));
    await Future.value();
    expect(cnts, List.generate(5, (index) => 1));
    expect(last, List.generate(5, (index) => null));
    cs.add(ChangeEventReplace({0: 0, 1: 1}.lock));
    expect(cnts, [2, 2, 1, 1, 1]);
    expect(last[0], 0);
    expect(last[1], 1);
    cs.add(ChangeEventReplace({0: 0, 2: 2}.lock));
    expect(cnts, [2, 3, 2, 1, 1]);
    expect(last[1], null);
    expect(last[2], 2);

    for (var s in subs) {
      s.cancel();
    }
  });

  test('containsValue works', () async {
    final s = ValueStream<(ChangeEvent<int, int>, IMap<int, int>)>(sync: true);
    final t = CSTracker($(() => s.use.$1), $(() => s.use.$2));

    var cnts = [0, 0, 0];
    var lasts = [false, false, false];
    final subs = [1, 2, 3]
        .mapIndexedAndLast((i, y, _) => t.containsValue(y).listen((event) {
              cnts[i]++;
              lasts[i] = event;
            }))
        .toList();

    await Future.value();
    expect(cnts, [0, 0, 0]);

    s.add((
      KeyChanges({
        0: ChangeRecordValue(1),
        1: ChangeRecordValue(2),
        2: ChangeRecordDelete<int>()
      }.lock),
      {0: 1, 1: 2}.lock
    ));

    await Future.value();
    expect(cnts, [1, 1, 1]);
    expect(lasts, [true, true, false]);

    s.add((
      KeyChanges({
        0: ChangeRecordDelete<int>(),
        1: ChangeRecordValue(1),
        2: ChangeRecordValue(5)
      }.lock),
      {1: 1, 2: 5}.lock
    ));

    await Future.value();
    expect(cnts, [1, 2, 1]);
    expect(lasts, [true, false, false]);

    s.add((
      KeyChanges({1: ChangeRecordDelete<int>(), 2: ChangeRecordValue(3)}.lock),
      {2: 3}.lock
    ));

    await Future.value();
    expect(cnts, [2, 2, 2]);
    expect(lasts, [false, false, true]);

    s.add(
        (ChangeEventReplace({0: 1, 1: 2, 2: 6}.lock), {0: 1, 1: 2, 2: 6}.lock));

    await Future.value();
    expect(cnts, [3, 3, 3]);
    expect(lasts, [true, true, false]);

    for (var e in subs) {
      e.cancel();
    }
  });
}
