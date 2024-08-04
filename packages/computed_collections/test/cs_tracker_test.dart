import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
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
    await Future.value();
    expect(cnts, List.generate(5, (index) => 1));
    expect(last, List.generate(5, (index) => null));
    cs.add(ChangeEventReplace({0: 0, 1: 1}.lock));
    await Future.value();
    expect(cnts, [2, 2, 1, 1, 1]);
    expect(last[0], 0);
    expect(last[1], 1);
    cs.add(ChangeEventReplace({0: 0, 2: 2}.lock));
    await Future.value();
    expect(cnts, [2, 3, 2, 1, 1]);
    expect(last[1], null);
    expect(last[2], 2);

    subs.forEach((s) => s.cancel());
  });
}
