import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_record.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  test('snapshot works', () async {
    final s = ValueStream<Set<ChangeRecord<int, int>>>(sync: true);
    final m1 = IComputedMap.fromChangeStream(s);
    final m2 = m1.add(0, 1);
    IMap<int, int>? lastRes;
    final sub = m2.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {0: 1}.lock);
    s.add({ChangeRecordInsert(0, 1)});
    expect(lastRes, {0: 1}.lock);
    s.add({ChangeRecordUpdate(0, 1, 2)});
    expect(lastRes, {0: 1}.lock);
    s.add({ChangeRecordInsert(1, 2)});
    expect(lastRes, {0: 1, 1: 2}.lock);
    s.add({ChangeRecordDelete(0, 2)});
    expect(lastRes, {0: 1, 1: 2}.lock);
    s.add({
      ChangeRecordReplace({4: 5}.lock)
    });
    expect(lastRes, {0: 1, 4: 5}.lock);

    sub.cancel();
  });

  test('operator[] works', () async {
    final s = ValueStream<Set<ChangeRecord<int, int>>>(sync: true);
    final m1 = IComputedMap.fromChangeStream(s);
    final m2 = m1.add(0, 1);

    var callCnt1 = 0;
    int? lastRes1;
    final sub1 = m2[0].listen((event) {
      callCnt1++;
      lastRes1 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt1, 0);
    await Future.value();
    expect(callCnt1, 1);
    expect(lastRes1, 1);

    s.add({ChangeRecordInsert(0, 1)});
    await Future.value();
    expect(callCnt1, 1);

    s.add({ChangeRecordInsert(1, 2)});
    await Future.value();
    expect(callCnt1, 1);
    s.add({ChangeRecordUpdate(1, 2, 3)});
    await Future.value();
    expect(callCnt1, 1);
    s.add({ChangeRecordUpdate(0, 1, 4)});
    await Future.value();
    expect(callCnt1, 1);
    s.add({
      ChangeRecordReplace({5: 6}.lock)
    });
    await Future.value();
    expect(callCnt1, 1);

    var callCnt2 = 0;
    int? lastRes2;
    final sub2 = m2[1].listen((event) {
      callCnt2++;
      lastRes2 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt2, 0);
    await Future.value();
    expect(callCnt2, 1);
    expect(lastRes2, null);

    s.add({ChangeRecordDelete(5, 6)});
    await Future.value();
    expect(callCnt1, 1);
    expect(callCnt2, 1);
    s.add({ChangeRecordInsert(1, 2)});
    await Future.value();
    expect(callCnt1, 1);
    expect(callCnt2, 2);
    expect(lastRes2, 2);
    s.add({ChangeRecordUpdate(1, 2, 3)});
    await Future.value();
    expect(callCnt1, 1);
    expect(callCnt2, 3);
    expect(lastRes2, 3);
    s.add({
      ChangeRecordReplace({1: 4}.lock)
    });
    await Future.value();
    expect(callCnt1, 1);
    expect(callCnt2, 4);
    expect(lastRes2, 4);

    sub1.cancel();
    sub2.cancel();

    s.add({
      ChangeRecordReplace({0: 3, 1: 5}.lock)
    });
    await Future.value();
    expect(callCnt1, 1); // The listeners have been cancelled
    expect(callCnt2, 4);
  });

  test('propagates the change stream', () async {
    final s = ValueStream<Set<ChangeRecord<int, int>>>(sync: true);
    final m1 = IComputedMap.fromChangeStream(s);
    final m2 = m1.add(0, 1);
    ISet<ChangeRecord<int, int>>? lastRes;
    var callCnt = 0;
    final sub = m2.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(callCnt, 0);
    s.add({ChangeRecordInsert(0, 1)});
    expect(callCnt, 0);
    s.add({ChangeRecordInsert(1, 2)});
    expect(callCnt, 1);
    expect(lastRes, {ChangeRecordInsert(1, 2)}.lock);
    s.add({ChangeRecordUpdate(0, 1, 2)});
    expect(callCnt, 1);
    s.add({ChangeRecordUpdate(1, 2, 3)});
    expect(callCnt, 2);
    expect(lastRes, {ChangeRecordUpdate(1, 2, 3)}.lock);
    s.add({ChangeRecordDelete(0, 2)});
    expect(callCnt, 2);
    s.add({ChangeRecordDelete(1, 3)});
    expect(callCnt, 3);
    expect(lastRes, {ChangeRecordDelete(1, 3)}.lock);
    s.add({
      ChangeRecordReplace({0: 5, 1: 6, 2: 7}.lock)
    });
    expect(callCnt, 4);
    expect(
        lastRes,
        {
          ChangeRecordReplace({0: 1, 1: 6, 2: 7}.lock)
        }.lock);

    sub.cancel();
  });
}
