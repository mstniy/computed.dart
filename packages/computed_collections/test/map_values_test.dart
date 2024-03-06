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
  test('operator[] works', () async {
    final s = ValueStream<ISet<ChangeRecord<int, int>>>(sync: true);
    final m1 = IComputedMap.fromChangeStream(s);
    var cCnt = 0;
    final m2 = m1.mapValues((k, v) {
      cCnt++;
      return v + 1;
    });

    var callCnt1 = 0;
    int? lastRes1;
    final sub1 = m2[0].listen((event) {
      callCnt1++;
      lastRes1 = event;
    }, (e) => fail(e.toString()));

    var callCnt2 = 0;
    int? lastRes2;
    final sub2 = m2[0].listen((event) {
      callCnt2++;
      lastRes2 = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(cCnt, 0);
    expect(callCnt1, 1);
    expect(lastRes1, null);
    expect(callCnt2, 1);
    expect(lastRes2, null);

    s.add({ChangeRecordInsert(0, 1)}.lock);
    await Future.value();
    expect(cCnt, 2);
    expect(callCnt1, 2);
    expect(lastRes1, 2);
    expect(callCnt2, 2);
    expect(lastRes2, 2);

    sub1.cancel();
  });

  test('propagates the change stream', () async {
    final s = ValueStream<ISet<ChangeRecord<int, int>>>(sync: true);
    final m1 = IComputedMap.fromChangeStream(s);
    final m2 = m1.mapValues((key, value) => value + 1);
    ISet<ChangeRecord<int, int>>? lastRes;
    var callCnt = 0;
    final sub = m2.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(callCnt, 0);
    s.add({ChangeRecordInsert(0, 1)}.lock);
    expect(callCnt, 1);
    expect(lastRes, {ChangeRecordInsert(0, 2)}.lock);

    s.add({ChangeRecordInsert(1, 2)}.lock);
    expect(callCnt, 2);
    expect(lastRes, {ChangeRecordInsert(1, 3)}.lock);

    s.add({ChangeRecordUpdate(0, 1, 2)}.lock);
    expect(callCnt, 3);
    expect(lastRes, {ChangeRecordUpdate(0, null, 3)}.lock);

    s.add({ChangeRecordDelete(0, 2)}.lock);
    expect(callCnt, 4);
    expect(lastRes, {ChangeRecordDelete(0, null)}.lock);

    s.add({ChangeRecordDelete(1, 3)}.lock);
    expect(callCnt, 5);
    expect(lastRes, {ChangeRecordDelete(1, null)}.lock);
    s.add({
      ChangeRecordReplace({0: 5, 1: 6, 2: 7}.lock)
    }.lock);
    expect(callCnt, 6);
    expect(
        lastRes,
        {
          ChangeRecordReplace({0: 6, 1: 7, 2: 8}.lock)
        }.lock);

    sub.cancel();
  });
}
