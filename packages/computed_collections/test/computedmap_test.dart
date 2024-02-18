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
  });
}
