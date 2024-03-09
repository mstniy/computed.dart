import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

void main() {
  test('snapshot works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = IComputedMap.fromChangeStream(s);
    IMap<int, int>? lastRes;
    final sub = m.snapshot.listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(lastRes, {}.lock);
    s.add(KeyChanges({0: ChangeRecordInsert(1)}.lock));
    expect(lastRes, {0: 1}.lock);
    s.add(KeyChanges({1: ChangeRecordInsert(2)}.lock));
    expect(lastRes, {0: 1, 1: 2}.lock);
    s.add(KeyChanges({1: ChangeRecordUpdate(3)}.lock));
    expect(lastRes, {0: 1, 1: 3}.lock);
    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    expect(lastRes, {1: 3}.lock);
    s.add(ChangeEventReplace({4: 5}.lock));
    expect(lastRes, {4: 5}.lock);

    sub.cancel();
  });

  test('operator[] works', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = IComputedMap.fromChangeStream(s);

    var callCnt1 = 0;
    int? lastRes1;
    final sub1 = m[0].listen((event) {
      callCnt1++;
      lastRes1 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt1, 0);
    await Future.value();
    expect(callCnt1, 1);
    expect(lastRes1, null);

    s.add(KeyChanges({0: ChangeRecordInsert(01)}.lock));
    await Future.value();
    expect(callCnt1, 2);
    expect(lastRes1, 1);

    s.add(KeyChanges({1: ChangeRecordInsert(2)}.lock));
    await Future.value();
    expect(callCnt1, 2);
    s.add(KeyChanges({1: ChangeRecordUpdate(3)}.lock));
    await Future.value();
    expect(callCnt1, 2);
    s.add(KeyChanges({0: ChangeRecordUpdate(4)}.lock));
    await Future.value();
    expect(callCnt1, 3);
    expect(lastRes1, 4);

    var callCnt2 = 0;
    int? lastRes2;
    final sub2 = m[0].listen((event) {
      callCnt2++;
      lastRes2 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt2, 0);
    await Future.value();
    expect(callCnt2, 1);
    expect(lastRes2, 4);

    s.add(KeyChanges({0: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(callCnt1, 4);
    expect(lastRes1, null);
    expect(callCnt2, 2);
    expect(lastRes2, null);
    s.add(KeyChanges({1: ChangeRecordDelete<int>()}.lock));
    await Future.value();
    expect(callCnt1, 4);
    expect(callCnt2, 2);
    s.add(ChangeEventReplace({4: 5}.lock));
    await Future.value();
    expect(callCnt1, 4);
    expect(callCnt2, 2);
    s.add(ChangeEventReplace({0: 0, 1: 1}.lock));
    await Future.value();
    expect(callCnt1, 5);
    expect(lastRes1, 0);
    expect(callCnt2, 3);
    expect(lastRes1, 0);

    int? lastRes3;
    var callCnt3 = 0;
    final sub3 = m[1].listen((event) {
      callCnt3++;
      lastRes3 = event;
    }, (e) => fail(e.toString()));

    expect(callCnt3, 0);
    await Future.value();
    expect(callCnt3, 1);
    expect(lastRes3, 1);

    s.add(KeyChanges({1: ChangeRecordUpdate(2)}.lock));
    await Future.value();
    expect(callCnt1, 5);
    expect(callCnt2, 3);
    expect(callCnt3, 2);
    expect(lastRes3, 2);

    await Future.value(); // No more updates
    expect(callCnt1, 5);
    expect(callCnt2, 3);
    expect(callCnt3, 2);

    sub1.cancel();

    s.add(ChangeEventReplace({0: 1, 1: 3}.lock));
    await Future.value();
    expect(callCnt1, 5); // The listener has been cancelled
    expect(callCnt2, 4);
    expect(lastRes2, 1);
    expect(callCnt3, 3);
    expect(lastRes3, 3);

    sub3.cancel();
    sub2.cancel();

    s.add(ChangeEventReplace({0: 2, 1: 4}.lock));
    await Future.value();
    expect(callCnt1, 5);
    expect(callCnt2, 4);
    expect(callCnt3, 3);
  });

  test('propagates exceptions', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = IComputedMap.fromChangeStream(s);
    IMap<int, int>? lastRes1;
    Object? lastExc1;
    var callCnt1 = 0;
    final sub1 = m.snapshot.listen((event) {
      callCnt1++;
      lastRes1 = event;
      lastExc1 = null;
    }, (e) {
      callCnt1++;
      lastRes1 = null;
      lastExc1 = e;
    });
    int? lastRes2;
    Object? lastExc2;
    var callCnt2 = 0;
    final sub2 = m[0].listen((event) {
      callCnt2++;
      lastRes2 = event;
      lastExc2 = null;
    }, (e) {
      callCnt2++;
      lastRes2 = null;
      lastExc2 = e;
    });
    expect(callCnt1, 0);
    expect(callCnt2, 0);
    await Future.value();
    expect(callCnt1, 1);
    expect(lastRes1, {}.lock);
    expect(callCnt2, 1);
    expect(lastRes2, null);
    s.addError(42);
    expect(callCnt1, 2);
    expect(lastExc1, 42);
    await Future.value();
    expect(callCnt2, 2);
    expect(lastExc2, 42);
    s.add(KeyChanges({0: ChangeRecordInsert(1)}.lock));
    await Future.value();
    expect(callCnt1, 2);
    expect(callCnt2, 2);

    Object? lastExc3;
    var callCnt3 = 0;
    final sub3 = m[1].listen(
        (event) => fail('Must have produced an exception instead'), (e) {
      callCnt3++;
      lastExc3 = e;
    });

    expect(callCnt3, 0);
    await Future.value();
    expect(callCnt3, 1);
    expect(lastExc3, 42);
    expect(callCnt1, 2);
    expect(callCnt2, 2);

    await Future.value();
    expect(callCnt1, 2); // No further callbacks
    expect(callCnt2, 2);
    expect(callCnt3, 1);

    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
  });

  test('propagates the change stream', () async {
    final s = ValueStream<ChangeEvent<int, int>>(sync: true);
    final m = IComputedMap.fromChangeStream(s);
    ChangeEvent<int, int>? lastRes;
    var callCnt = 0;
    final sub = m.changes.listen((event) {
      callCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(callCnt, 0);
    s.add(KeyChanges({0: ChangeRecordInsert(1)}.lock));
    expect(callCnt, 1);
    expect(lastRes, KeyChanges({0: ChangeRecordInsert(1)}.lock));

    sub.cancel();
  });

  group('mocks', () {
    test('can use fix/fixError', () async {
      final s = ValueStream<ChangeEvent<int, int>>(sync: true);
      final m = IComputedMap.fromChangeStream(s);
      IMap<int, int>? lastRes1;
      Object? lastExc1;
      var callCnt1 = 0;
      final sub1 = m.snapshot.listen((event) {
        callCnt1++;
        lastRes1 = event;
        lastExc1 = null;
      }, (e) {
        callCnt1++;
        lastRes1 = null;
        lastExc1 = e;
      });
      int? lastRes2;
      Object? lastExc2;
      var callCnt2 = 0;
      final sub2 = m[0].listen((event) {
        callCnt2++;
        lastRes2 = event;
        lastExc2 = null;
      }, (e) {
        callCnt2++;
        lastRes2 = null;
        lastExc2 = e;
      });
      int? lastRes3;
      Object? lastExc3;
      var callCnt3 = 0;
      final sub3 = m[1].listen((event) {
        callCnt3++;
        lastRes3 = event;
        lastExc3 = null;
      }, (e) {
        callCnt3++;
        lastRes3 = null;
        lastExc3 = e;
      });
      await Future.value();
      expect(callCnt1, 1);
      expect(callCnt2, 1);
      expect(callCnt3, 1);
      expect(lastRes1, {}.lock);
      expect(lastRes2, null);
      expect(lastRes3, null);

      m.fix({0: 1}.lock);

      expect(callCnt1, 2);
      expect(lastRes1, {0: 1}.lock);
      await Future.value();
      expect(callCnt2, 2);
      expect(lastRes2, 1);
      expect(callCnt3, 1);

      m.fixThrow(42);

      expect(callCnt1, 3);
      expect(lastExc1, 42);
      await Future.value();
      expect(callCnt2, 3);
      expect(callCnt3, 2);
      expect(lastExc2, 42);
      expect(lastExc3, 42);

      m.unmock();

      expect(callCnt1, 4);
      expect(lastRes1, {}.lock);
      await Future.value();
      expect(callCnt2, 4);
      expect(callCnt3, 3);
      expect(lastRes2, null);
      expect(lastRes3, null);

      sub1.cancel();
      sub2.cancel();
      sub3.cancel();
    });

    test('can use mock', () async {
      final s = ValueStream<ChangeEvent<int, int>>(sync: true);
      final s2 = ValueStream<IMap<int, int>>(sync: true);
      final m = IComputedMap.fromChangeStream(s);
      IMap<int, int>? lastRes1;
      Object? lastExc1;
      var callCnt1 = 0;
      final sub1 = m.snapshot.listen((event) {
        callCnt1++;
        lastRes1 = event;
        lastExc1 = null;
      }, (e) {
        callCnt1++;
        lastRes1 = null;
        lastExc1 = e;
      });
      int? lastRes2;
      Object? lastExc2;
      var callCnt2 = 0;
      final sub2 = m[0].listen((event) {
        callCnt2++;
        lastRes2 = event;
        lastExc2 = null;
      }, (e) {
        callCnt2++;
        lastRes2 = null;
        lastExc2 = e;
      });

      await Future.value();
      expect(callCnt1, 1);
      expect(callCnt2, 1);
      expect(lastRes1, {}.lock);
      expect(lastRes2, null);

      s2.add({0: 1}.lock);

      m.mock(() => s2.use);
      expect(callCnt1, 1);
      await Future.value();
      expect(callCnt1, 2);
      expect(lastRes1, {0: 1}.lock);
      expect(callCnt2, 1);
      await Future.value();
      expect(callCnt2, 2);
      expect(lastRes2, 1);

      m.mock(() => throw 42);
      expect(callCnt1, 3);
      expect(lastExc1, 42);
      expect(callCnt2, 2);
      await Future.value();
      expect(callCnt2, 3);
      expect(lastExc2, 42);

      sub1.cancel();
      sub2.cancel();
    });
  });
}
