import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  group('fromChangeStream', () {
    test('snapshot works', () async {
      final s = ValueStream<Set<ChangeRecord<int, int>>>(sync: true);
      final m = IComputedMap.fromChangeStream($(() => s.use));
      IMap<int, int>? lastRes;
      final sub = m.snapshot.listen((event) {
        lastRes = event;
      }, (e) => fail(e.toString()));
      await Future.value();
      expect(lastRes, {}.lock);
      s.add({ChangeRecordInsert(0, 1)});
      expect(lastRes, {0: 1}.lock);
      s.add({ChangeRecordInsert(1, 2)});
      expect(lastRes, {0: 1, 1: 2}.lock);
      s.add({ChangeRecordUpdate(1, 2, 3)});
      expect(lastRes, {0: 1, 1: 3}.lock);
      s.add({ChangeRecordDelete(0, 1)});
      expect(lastRes, {1: 3}.lock);
      s.add({
        ChangeRecordReplace({4: 5}.lock)
      });
      expect(lastRes, {4: 5}.lock);

      sub.cancel();
    });

    test('operator[] works', () async {
      final s = ValueStream<Set<ChangeRecord<int, int>>>(sync: true);
      final m = IComputedMap.fromChangeStream($(() => s.use));
      final c = m[0];
      var callCnt1 = 0;
      int? lastRes1;
      final sub1 = c.listen((event) {
        callCnt1++;
        lastRes1 = event;
      }, (e) => fail(e.toString()));

      expect(callCnt1, 0);
      await Future.value();
      expect(callCnt1, 1);
      expect(lastRes1, null);

      s.add({ChangeRecordInsert(0, 1)});
      expect(callCnt1, 2);
      expect(lastRes1, 1);
      s.add({ChangeRecordInsert(1, 2)});
      expect(callCnt1, 2);
      s.add({ChangeRecordUpdate(1, 2, 3)});
      expect(callCnt1, 2);
      s.add({ChangeRecordUpdate(0, 1, 4)});
      expect(callCnt1, 3);
      expect(lastRes1, 4);
      s.add({ChangeRecordDelete(0, 4)});
      expect(callCnt1, 4);
      expect(lastRes1, null);
      s.add({ChangeRecordDelete(1, 3)});
      expect(callCnt1, 4);
      s.add({
        ChangeRecordReplace({4: 5}.lock)
      });
      expect(callCnt1, 4);
      s.add({
        ChangeRecordReplace({0: 0, 1: 1}.lock)
      });
      expect(callCnt1, 5);
      expect(lastRes1, 0);

      int? lastRes2;
      var callCnt2 = 0;
      final sub2 = m[1].listen((event) {
        callCnt2++;
        lastRes2 = event;
      }, (e) => fail(e.toString()));

      expect(callCnt2, 0);
      await Future.value();
      expect(callCnt2, 1);
      expect(lastRes2, 1);

      s.add({ChangeRecordUpdate(1, 1, 2)});
      expect(callCnt1, 5);
      expect(callCnt2, 2);
      expect(lastRes2, 2);

      await Future.value(); // No more updates
      expect(callCnt1, 5);
      expect(callCnt2, 2);

      sub1.cancel();

      s.add({
        ChangeRecordReplace({0: 1, 1: 3}.lock)
      });
      expect(callCnt1, 5); // The listener has been cancelled
      expect(callCnt2, 3);
      expect(lastRes2, 3);

      sub2.cancel();

      s.add({
        ChangeRecordReplace({0: 2, 1: 4}.lock)
      });
      expect(callCnt1, 5); // The listener has been cancelled
      expect(callCnt2, 3); // The listener has been cancelled
    });
  });
}
