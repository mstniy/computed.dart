import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  test('incremental update works', () async {
    final s = ValueStream<ISet<ChangeRecord<int, int>>>(sync: true);
    final m1 = IComputedMap.fromChangeStream(s);
    final m2 = m1.mapValues((k, v) => v + 1);
    IMap<int, int>? lastRes;
    final sub = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {}.lock);
    s.add({ChangeRecordInsert(0, 1)}.lock);
    await Future.value();
    expect(lastRes, {0: 2}.lock);
    s.add({ChangeRecordUpdate(0, 1, 2)}.lock);
    await Future.value();
    expect(lastRes, {0: 3}.lock);
    s.add({ChangeRecordInsert(1, 1)}.lock);
    await Future.value();
    expect(lastRes, {0: 3, 1: 2}.lock);
    s.add({ChangeRecordDelete(0, 2)}.lock);
    await Future.value();
    expect(lastRes, {1: 2}.lock);
    s.add({
      ChangeRecordReplace({4: 5}.lock)
    }.lock);
    await Future.value();
    expect(lastRes, {4: 6}.lock);

    sub.cancel();
  });

  test('initial computation works', () async {
    final s = ValueStream<ISet<ChangeRecord<int, int>>>(sync: true);
    s.add({
      ChangeRecordReplace({0: 1, 2: 3}.lock)
    }.lock);
    final m1 = IComputedMap.fromChangeStream(s);
    final sub1 = m1.snapshot.listen(null, null); // Force m1 to be computed
    await Future.value();

    final m2 = m1.mapValues((k, v) {
      return v + 1;
    });
    IMap<int, int>? lastRes;
    final sub2 = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {0: 2, 2: 4}.lock);

    sub1.cancel();
    sub2.cancel();
  });

  // Nothing to test further, as mapValues just returns a ChangeStreamComputedMap
}
