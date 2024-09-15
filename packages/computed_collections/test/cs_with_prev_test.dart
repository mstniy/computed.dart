import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('works', () async {
    final s = ValueStream<int>.seeded(0, sync: true);
    final m = ComputedMap<int, int>.fromChangeStreamWithPrev((m) {
      return KeyChanges({s.use: ChangeRecordValue((m?[s.use] ?? 0) + 1)}.lock);
    });

    // Do it twice to test that the internal state gets reset properly
    //  upon cancellation
    for (var i = 0; i < 2; i++) {
      var cnt = 0;
      IMap<int, int>? snapshot;

      var sub = m.snapshot.listen((event) {
        cnt++;
        snapshot = event;
      });

      await Future.value();
      expect(cnt, 1);
      expect(snapshot, {0: 1}.lock);

      s.add(1);
      expect(cnt, 2);
      expect(snapshot, {0: 1, 1: 1}.lock);

      s.add(0);
      expect(cnt, 3);
      expect(snapshot, {0: 2, 1: 1}.lock);

      sub.cancel();

      // Note that [s] is still set to 0, so we are ready for the next iteration
    }
  });

  test('works if not subscribed to the snapshot', () async {
    final s = ValueStream<int>.seeded(0, sync: true);
    final m = ComputedMap<int, int>.fromChangeStreamWithPrev((m) {
      return KeyChanges({s.use: ChangeRecordValue((m?[s.use] ?? 0) + 1)}.lock);
    });

    // Do it twice to test that the internal state gets reset properly
    //  upon cancellation
    for (var i = 0; i < 2; i++) {
      var cnt = 0;
      ChangeEvent<int, int>? change;

      var sub = m.changes.listen((event) {
        cnt++;
        change = event;
      });

      await Future.value();
      expect(cnt, 1);
      expect(change, KeyChanges({0: ChangeRecordValue(1)}.lock));

      s.add(1);
      expect(cnt, 2);
      expect(change, KeyChanges({1: ChangeRecordValue(1)}.lock));

      s.add(0);
      expect(cnt, 3);
      expect(change, KeyChanges({0: ChangeRecordValue(2)}.lock));

      sub.cancel();

      // Note that [s] is still set to 0, so we are ready for the next iteration
    }
  });

  test('attributes are coherent', () async {
    final m = ComputedMap.fromChangeStreamWithPrev(
        (_) => KeyChanges({0: ChangeRecordValue(1)}.lock));
    await testCoherenceInt(m, {0: 1}.lock);
  });
}
