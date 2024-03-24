import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed/utils/streams.dart';
import 'package:test/test.dart';

ComputedSubscription<T> subscribeTo<T>(
    Computed<T> c, void Function(T value) f) {
  return c.listen(f, (e) => fail(e.toString()));
}

void main() {
  group('ComputationCache', () {
    test('works', () async {
      final cache = ComputationCache<int, int>();
      final s1 = ValueStream.seeded(1, sync: true);
      final s2 = ValueStream.seeded(2, sync: true);
      final callCnts = [0, 0, 0, 0, 0];
      final c0 = cache.wrap(1, () {
        callCnts[0]++;
        return s1.use;
      });
      final c1 = cache.wrap(1, () {
        callCnts[1]++;
        return s1.use;
      });
      final c2 = cache.wrap(1, () {
        callCnts[2]++;
        return s1.use;
      });
      final c3 = cache.wrap(2, () {
        callCnts[3]++;
        return s2.use;
      });
      final c4 = cache.wrap(2, () {
        callCnts[4]++;
        return s2.use;
      });

      final lCnts = [0, 0, 0, 0, 0];
      final lastValues = <int?>[null, null, null, null, null];

      listener(int idx) {
        return (int e) {
          lCnts[idx]++;
          lastValues[idx] = e;
        };
      }

      var sub1 = subscribeTo(c1, listener(1));
      await Future.value();
      expect(callCnts, [0, 4, 0, 0, 0]);
      expect(lCnts, [0, 1, 0, 0, 0]);
      expect(lastValues, [null, 1, null, null, null]);

      var sub0 = subscribeTo(c0, listener(0));
      await Future.value();
      expect(callCnts, [0, 4, 0, 0, 0]);
      expect(lCnts, [1, 1, 0, 0, 0]);
      expect(lastValues, [1, 1, null, null, null]);

      var sub3 = subscribeTo(c3, listener(3));
      await Future.value();
      expect(callCnts, [0, 4, 0, 4, 0]);
      expect(lCnts, [1, 1, 0, 1, 0]);
      expect(lastValues, [1, 1, null, 2, null]);

      var sub4 = subscribeTo(c4, listener(4));
      await Future.value();
      expect(callCnts, [0, 4, 0, 4, 0]);
      expect(lCnts, [1, 1, 0, 1, 1]);
      expect(lastValues, [1, 1, null, 2, 2]);

      s1.add(3);
      expect(callCnts, [0, 6, 0, 4, 0]);
      expect(lCnts, [2, 2, 0, 1, 1]);
      expect(lastValues, [3, 3, null, 2, 2]);

      s2.add(4);
      expect(callCnts, [0, 6, 0, 6, 0]);
      expect(lCnts, [2, 2, 0, 2, 2]);
      expect(lastValues, [3, 3, null, 4, 4]);

      sub1.cancel();
      s1.add(5);
      expect(callCnts, [0, 8, 0, 6, 0]);
      expect(lCnts, [3, 2, 0, 2, 2]);
      expect(lastValues, [5, 3, null, 4, 4]);

      sub1 = subscribeTo(c1, listener(1));
      await Future.value();
      expect(callCnts, [0, 8, 0, 6, 0]);
      expect(lCnts, [3, 3, 0, 2, 2]);
      expect(lastValues, [5, 5, null, 4, 4]);

      s1.add(6);
      expect(callCnts, [0, 10, 0, 6, 0]);
      expect(lCnts, [4, 4, 0, 2, 2]);
      expect(lastValues, [6, 6, null, 4, 4]);

      sub0.cancel();
      sub1.cancel();
      s1.add(7);
      expect(callCnts, [0, 10, 0, 6, 0]);
      expect(lCnts, [4, 4, 0, 2, 2]);
      expect(lastValues, [6, 6, null, 4, 4]);

      sub0 = subscribeTo(c0, listener(0));
      await Future.value();
      expect(callCnts, [4, 10, 0, 6, 0]);
      expect(lCnts, [5, 4, 0, 2, 2]);
      expect(lastValues, [7, 6, null, 4, 4]);

      sub1 = subscribeTo(c1, listener(1));
      await Future.value();
      expect(callCnts, [4, 10, 0, 6, 0]);
      expect(lCnts, [5, 5, 0, 2, 2]);
      expect(lastValues, [7, 7, null, 4, 4]);

      s1.add(8);
      expect(callCnts, [6, 10, 0, 6, 0]);
      expect(lCnts, [6, 6, 0, 2, 2]);
      expect(lastValues, [8, 8, null, 4, 4]);

      sub1.cancel();
      s1.add(9);
      expect(callCnts, [8, 10, 0, 6, 0]);
      expect(lCnts, [7, 6, 0, 2, 2]);
      expect(lastValues, [9, 8, null, 4, 4]);

      final sub2 = subscribeTo(c2, listener(2));
      await Future.value();
      expect(callCnts, [8, 10, 0, 6, 0]);
      expect(lCnts, [7, 6, 1, 2, 2]);
      expect(lastValues, [9, 8, 9, 4, 4]);

      s1.add(10); // c0 is still the lead for key=1
      expect(callCnts, [10, 10, 0, 6, 0]);
      expect(lCnts, [8, 6, 2, 2, 2]);
      expect(lastValues, [10, 8, 10, 4, 4]);

      sub3.cancel();
      sub4.cancel();
      s2.addError(42);
      sub3 = c3.listen((event) => fail('expected error'), (e) {
        lCnts[3]++;
        lastValues[3] = e;
      });
      await Future.value();

      // Two calls throw NVE, third call throws 42 Computed does not do an idempotency call
      expect(callCnts, [10, 10, 0, 9, 0]);
      expect(lCnts, [8, 6, 2, 3, 2]);
      expect(lastValues, [10, 8, 10, 42, 4]);

      sub3.cancel();
      sub4 = c4.listen((event) => fail('expected error'), (e) {
        lCnts[4]++;
        lastValues[4] = e;
      });
      await Future.value();
      // Now c4 is the lead for key=2
      expect(callCnts, [10, 10, 0, 9, 3]);
      expect(lCnts, [8, 6, 2, 3, 3]);
      expect(lastValues, [10, 8, 10, 42, 42]);

      sub0.cancel();
      sub1.cancel();
      sub2.cancel();
      sub3.cancel();
      sub4.cancel();
    });

    test('can mock/unmock', () async {
      final cache = ComputationCache<int, int>();
      var lCnt1 = 0;
      int? lastRes1;
      final c1 = cache.wrap(1, () => 1);
      final sub = c1.listen((value) {
        lCnt1++;
        lastRes1 = value;
      }, (e) => fail(e.toString()));
      await Future.value();
      expect(lCnt1, 1);
      expect(lastRes1, 1);
      // Mock the computations
      cache.mock((key) => key + 1);
      // Keys with leader are mocked
      expect(lCnt1, 2);
      expect(lastRes1, 2);
      // Keys without leaders must also be mocked
      final c = cache.wrap(0, () => 0);
      var lCnt = 0;
      int? lastRes;
      var sub0 = c.listen((event) {
        lCnt++;
        lastRes = event;
      }, (e) => fail(e.toString()));
      await Future.value();
      expect(lCnt, 1);
      expect(lastRes, 1); // And not 0
      sub0.cancel(); // Key 0 loses its leader
      // Unmock the computations
      cache.unmock();
      // Must unmock keys with existing leaders
      expect(lCnt1, 3);
      expect(lastRes1, 1);
      // Must unmock keys without existing leaders
      sub0 = c.listen((event) {
        lCnt++;
        lastRes = event;
      }, (e) => fail(e.toString()));
      await Future.value();
      expect(lCnt, 2);
      expect(lastRes, 0);

      sub.cancel();
    });
  });
}
