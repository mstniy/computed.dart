import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/src/computed.dart';
import 'package:test/test.dart';

void main() {
  test('unlistened computations are not computed', () {
    Computed(() => fail('must not be computed'));
  });

  group('streams', () {
    test('can be used as data source', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      int? lastRes;

      final sub = Computed(() => source.use * 2).listen((event) {
        lastRes = event;
      }, (e) => fail(e.toString()));

      try {
        controller.add(0);
        expect(lastRes, 0);
        controller.add(1);
        expect(lastRes, 2);
      } finally {
        sub.cancel();
      }
    });

    test('react does not memoize the values produced by the stream', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      // Also test that calling both .use and .react works
      for (var callBoth in [false, true]) {
        for (var reactFirst in [false, if (callBoth) true]) {
          int cCnt = 0;
          int lCnt = 0;
          int? lastRes;

          final sub = Computed(() {
            cCnt++;
            if (callBoth) {
              if (reactFirst) source.react((p0) {}, null);
              source.use;
            }
            int? reactRes;
            source.react((val) => reactRes = val, null);
            return reactRes != null ? (reactRes! * 2) : null;
          }).listen((event) {
            lCnt++;
            lastRes = event;
          }, (e) => fail(e.toString()));

          try {
            final lCntBase = callBoth ? 0 : 1;
            await Future.value(0);
            expect(cCnt, 2);
            expect(lCnt, lCntBase);
            expect(lastRes, null);
            controller.add(0);
            expect(cCnt, 4);
            expect(lCnt, lCntBase + 1);
            expect(lastRes, 0);
            controller.add(0);
            expect(cCnt, 6);
            expect(lCnt, lCntBase + 1);
            controller.add(1);
            expect(cCnt, 8);
            expect(lCnt, lCntBase + 2);
            expect(lastRes, 2);
          } finally {
            sub.cancel();
          }
        }
      }
    });

    test('can switch from use to react', () async {
      // Note that the other direction (react -> use) does not work.
      // I can't think of a way to make it work without introducing
      // additional bookkeeping (ie. overhead),
      // nor a real-world scenario where it would be useful.
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      var useUse = true;
      var cnt = 0;

      final c = Computed(() {
        cnt++;
        useUse ? source.use : source.react((p0) {}, null);
      });

      final sub = c.listen(null, (e) => fail(e.toString()));

      try {
        expect(cnt, 2);
        controller.add(0);
        expect(cnt, 4);
        controller.add(0);
        expect(cnt, 4);
        useUse = false;
        controller.add(1);
        expect(cnt, 6);
        controller.add(1);
        expect(cnt, 8);
      } finally {
        sub.cancel();
      }
    });

    test('.react throws if the stream has no new value', () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      final controller2 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source2 = controller2.stream;

      int? expectation1; // If null, expect NVE
      int? expectation2;
      var cCnt = 0;

      final c2 = Computed(() => 42);

      final c = Computed(() {
        // Subscribe to both sources and c2
        cCnt++;
        c2.use;
        var flag = false;
        source1.react((val) {
          flag = true;
          expect(val, expectation1);
        }, null);
        if (!flag) expect(expectation1, null);
        flag = false;
        source2.react((val) {
          flag = true;
          expect(val, expectation2);
        }, null);
        if (!flag) expect(expectation2, null);
      });

      final sub = c.listen(null, (e) => fail(e.toString()));

      try {
        expect(cCnt, 2);
        expectation1 = 0;
        controller1.add(0);
        expect(cCnt, 4);
        controller1.add(0);
        expect(cCnt, 6);
        expectation1 = null;
        expectation2 = 1;
        controller2.add(1);
        expect(cCnt, 8);
        controller2.add(1);
        expect(cCnt, 10);
        expectation2 = 2;
        controller2.add(2);
        expect(cCnt, 12);
        expectation1 = 2;
        expectation2 = null;
        controller1.add(2);
        expect(cCnt, 14);
        expectation1 = null;
        c2.fix(43);
        expect(cCnt, 16);
      } finally {
        sub.cancel();
      }
    });

    test(
        '(regression) .react on non-changed stream does not mark computation dirty',
        () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      final controller2 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source2 = controller2.stream;

      var lCnt = 0;

      final c1 = Computed(() {
        source2.react((p0) {}, null);

        return lCnt;
      });

      final c2 = Computed(() {
        source1.react((p0) {}, null);
        try {
          c1.use;
        } on NoValueException {
          // Pass
        }

        return lCnt;
      });

      final sub = c2.listen((event) {
        lCnt++;
      }, (e) => fail(e.toString()));

      try {
        await Future.value();
        expect(lCnt, 1);
        controller2.add(0);
        await Future.value();
        expect(lCnt, 2);
        controller1.add(0);
        await Future.value();
        expect(lCnt, 3);
        controller1.add(0);
        await Future.value();
        expect(lCnt, 4);
      } finally {
        sub.cancel();
      }
    });

    test('(regression) can subscribe to constant computations', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      var cCnt = 0;

      final c2 = Computed(() => 42);

      var expectation1 = 42;
      int? expectation2; // If null, expect NoValueException

      final c = Computed(() {
        cCnt++;
        // Subscribe to the sources and c2
        expect(c2.use, expectation1);
        try {
          expect(source.use, expectation2);
        } on NoValueException {
          expect(expectation2, null);
        }
      });

      final sub = c.listen(null, (e) => fail(e.toString()));

      try {
        expect(cCnt, 2);
        expectation2 = 0;
        controller.add(0);
        expect(cCnt, 4);
        controller.add(0);
        expect(cCnt, 4);
        expectation2 = 1;
        controller.add(1);
        expect(cCnt, 6);
        c2.fix(42);
        expect(cCnt, 6);
        c2.unmock();
        expect(cCnt, 6);
        expectation1 = 43;
        c2.fix(43);
        expect(cCnt, 8);
        c2.fix(43);
        expect(cCnt, 8);
        expectation1 = 42;
        c2.unmock();
        expect(cCnt, 10);
        source.mockEmit(1);
        expect(cCnt, 10);
        expectation2 = 2;
        source.mockEmit(2);
        expect(cCnt, 12);
      } finally {
        sub.cancel();
      }
    });

    test('mockEmit[Error] works', () async {
      final source = Stream.empty();

      int ctr = 0;
      bool? lastWasError;
      int? lastRes;
      Object? lastError;

      final sub = Computed(() => source.use).listen((event) {
        ctr++;
        lastWasError = false;
        lastRes = event;
      }, (e) {
        ctr++;
        lastWasError = true;
        lastError = e;
      });

      try {
        source.mockEmit(0);
        expect(ctr, 1);
        expect(lastWasError, false);
        expect(lastRes, 0);
        source.mockEmit(0);
        expect(ctr, 1);
        source.mockEmit(1);
        expect(ctr, 2);
        expect(lastWasError, false);
        expect(lastRes, 1);
        source.mockEmitError(1);
        expect(ctr, 3);
        expect(lastWasError, true);
        expect(lastError, 1);
        source.mockEmitError(2);
        expect(ctr, 4);
        expect(lastWasError, true);
        expect(lastError, 2);
        source.mockEmitError(2);
        expect(ctr, 4);
        source.mockEmit(3);
        expect(ctr, 5);
        expect(lastWasError, false);
        expect(lastRes, 3);
      } finally {
        sub.cancel();
      }
    });

    test('can be used as listeners', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      for (var isBroadcast in [false, true]) {
        bool? lastWasError;
        int? lastRes;
        Object? lastError;
        var ctr = 0;

        final c = Computed(() => source.use * 2);

        final stream = isBroadcast ? c.asBroadcastStream : c.asStream;

        final sub = stream.listen((event) {
          ctr++;
          lastWasError = false;
          lastRes = event;
        }, onError: (e) {
          ctr++;
          lastWasError = true;
          lastError = e;
        });

        try {
          await Future.value(); // Sanity check
          expect(ctr, 0);
          controller.add(0);
          await Future
              .value(); // As Stream-s call their listeners in the next tick
          expect(ctr, 1);
          expect(lastWasError, false);
          expect(lastRes, 0);
          controller.add(1);
          await Future.value();
          expect(ctr, 2);
          expect(lastRes, 2);
          controller.addError(2);
          await Future.value();
          expect(ctr, 3);
          expect(lastWasError, true);
          expect(lastError, 2);
          await Future.value(); // Sanity check
          expect(ctr, 3);
        } finally {
          sub.cancel();
        }

        try {
          stream.listen((event) {});
          if (!isBroadcast) fail("should have thrown");
        } on StateError catch (e) {
          expect(isBroadcast, false);
          // The returned stream is not a broadcast stream
          expect(e.message, contains('Stream has already been listened to.'));
        }
      }
    });

    test('can pass errors to computations', () {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      Object? expectation; // If null, don't expect an exception

      var subCnt = 0;

      final c = Computed(() {
        try {
          source.use;
          expect(expectation, null);
        } on NoValueException {
          // Do not run the exception expect in this case
          rethrow;
        } catch (e) {
          expect(e, expectation);
        }
        return subCnt; // To keep the listener call from getting memoized away
      });

      final sub = c.listen((event) {
        subCnt++;
      }, (e) => fail(e.toString()));

      try {
        controller.add(0);
        expect(subCnt, 1);
        expectation = 1;
        controller.addError(1);
        expect(subCnt, 2);
        // Exceptions are also memoized
        controller.addError(1);
        expect(subCnt, 2);
        expectation = 2;
        controller.addError(2);
        expect(subCnt, 3);
        expectation = null;
        controller.add(3);
        expect(subCnt, 4);
        controller.add(3);
        expect(subCnt, 4);
      } finally {
        sub.cancel();
      }
    });
  });

  group('futures', () {
    test('can be used as data sources', () async {
      final completer = Completer<int>();
      final future = completer.future;

      final x2 = Computed(() => future.use * 2);
      final x3 = Computed(() => x2.use * future.use);

      var callCnt = 0;

      final sub = x3.listen((event) {
        callCnt++;
        expect(event, 8);
      }, (e) => fail(e.toString()));

      try {
        completer.complete(2);
        await Future.value();
        expect(callCnt, 1);
      } finally {
        sub.cancel();
      }
    });

    test('can pass rejections to computations', () async {
      final completer = Completer<int>();
      final future = completer.future;

      final c = Computed(() {
        try {
          future.use;
          fail("Must have thrown");
        } on NoValueException {
          rethrow;
        } catch (e) {
          expect(e, 1);
        }
      });

      var callCnt = 0;

      final sub = c.listen((event) {
        callCnt++;
      }, (e) => fail(e.toString()));

      try {
        completer.completeError(1);
        await Future.value(0);
        expect(callCnt, 1);
      } finally {
        sub.cancel();
      }
    });

    test('can be cancelled', () async {
      final completer = Completer<int>();
      final future = completer.future;

      final x = Computed(() {
        future.use;
        fail('Must not run the computation');
      });

      final sub = x.listen((event) {
        fail('Must not call the listener');
      }, (e) => fail(e.toString()));

      sub.cancel();

      completer.complete(0);

      await Future.value();

      // Nothing should be run
    });
  });

  test('computation listeners can be changed', () {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    final c = Computed(() => source.use);

    final sub = c.listen((event) {
      fail("Must not run");
    }, (e) => fail("Must not run"));

    try {
      int ctr = 0;
      bool? lastWasError;
      int? lastValue;
      Object? lastError;
      sub.onData((data) {
        ctr++;
        lastWasError = false;
        lastValue = data;
      });
      sub.onError((e) {
        ctr++;
        lastWasError = true;
        lastError = e;
      });

      controller.add(0);
      expect(ctr, 1);
      expect(lastWasError, false);
      expect(lastValue, 0);
      controller.addError(1);
      expect(ctr, 2);
      expect(lastWasError, true);
      expect(lastError, 1);
    } finally {
      sub.cancel();
    }
  });

  test('computations can use other computations', () {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    int? lastRes;

    final x2 = Computed(() => source.use * 2);

    final sub = Computed(() => x2.use + 1).listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));

    try {
      controller.add(0);
      expect(lastRes, 1);
      controller.add(1);
      expect(lastRes, 3);
    } finally {
      sub.cancel();
    }
  });

  test('computations are memoized', () {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    int? lastRes;

    final x2 = Computed<int>(() => source.use * source.use);

    var callCnt = 0;

    final sub = Computed(() {
      callCnt += 1;
      return x2.use;
    }).listen((event) {
      lastRes = event;
    }, (e) => fail(e.toString()));

    expect(callCnt, 2);

    try {
      controller.add(0);
      expect(lastRes, 0);
      expect(callCnt, 4);
      controller.add(1);
      expect(lastRes, 1);
      expect(callCnt, 6);
      controller.add(1);
      expect(lastRes, 1);
      expect(callCnt, 6);
      controller.add(-1);
      expect(lastRes, 1);
      expect(callCnt, 6);
    } finally {
      sub.cancel();
    }
  });

  test('latest pattern works', () {
    final controller1 = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source1 = controller1.stream;

    final controller2 = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source2 = controller2.stream;

    final c = Computed(() {
      int? s1prev, s1now, s2now;
      try {
        s1prev = source1.prev;
      } on NoValueException {
        //Pass
      }
      try {
        s1now = source1.use;
      } on NoValueException {
        //Pass
      }
      try {
        s2now = source2.use;
      } on NoValueException {
        //Pass
      }
      if (s1now == null && s2now == null) {
        throw NoValueException(); // Give up
      }
      if (s1prev != s1now) return s1now;
      return s2now;
    });

    var expectation = 0;
    var callCnt = 0;

    final sub = c.listen((event) {
      callCnt++;
      expect(event, expectation);
    }, (e) => fail(e.toString()));

    try {
      controller1.add(0);
      expect(callCnt, 1);
      expectation = 1;
      controller2.add(1);
      expect(callCnt, 2);
      expectation = 2;
      controller1.add(2);
      expect(callCnt, 3);
      expectation = 3;
      controller1.add(3);
      expect(callCnt, 4);
      expectation = 4;
      controller2.add(4);
      expect(callCnt, 5);
    } finally {
      sub.cancel();
    }
  });

  group('respects topological order', () {
    test('on upstream updates', () {
      for (var streamFirst in [false, true]) {
        // Run the test twice to make sure the order of operations doesn't matter
        final controller = StreamController<int>.broadcast(
            sync: true); // Use a broadcast stream to make debugging easier
        final source = controller.stream;

        final outputs = <int>[];

        final x2 = Computed(() => source.use * 2);

        final x2Plusx = streamFirst
            ? Computed<int>(() => source.use + x2.use)
            : Computed<int>(() => x2.use + source.use);

        final sub = x2Plusx.listen((output) {
          outputs.add(output);
        }, (e) => fail(e.toString()));

        try {
          controller.add(0);
          expect(outputs, orderedEquals([0]));
          controller.add(1);
          expect(outputs, orderedEquals([0, 3]));
        } finally {
          sub.cancel();
        }
      }
    });

    test('on upstream updates (bigger)', () {
      // Test with different combinations of orderings
      for (var a in [false, true]) {
        for (var b in [false, true]) {
          final controller1 = StreamController<int>.broadcast(
              sync: true); // Use a broadcast stream to make debugging easier
          final source1 = controller1.stream;

          final controller2 = StreamController<int>.broadcast(
              sync: true); // Use a broadcast stream to make debugging easier
          final source2 = controller2.stream;

          final c1 = Computed(() {
            final x = source1.use + source2.use;
            return x;
          });
          final c2 = Computed(
              () => a ? (c1.use + source1.use) : (source1.use + c1.use));
          final c3 = Computed(
              () => b ? (c1.use + source2.use) : (source2.use + c1.use));

          final outputs2 = <int>[];
          final outputs3 = <int>[];

          final sub2 = c2.listen((output) {
            outputs2.add(output);
          }, (e) => fail(e.toString()));

          final sub3 = c3.listen((output) {
            outputs3.add(output);
          }, (e) => fail(e.toString()));

          try {
            controller1.add(0);
            expect(outputs2, orderedEquals([]));
            expect(outputs3, orderedEquals([]));
            controller2.add(1);
            expect(outputs2, orderedEquals([1]));
            expect(outputs3, orderedEquals([2]));
            controller1.add(2);
            expect(outputs2, orderedEquals([1, 5]));
            expect(outputs3, orderedEquals([2, 4]));
          } finally {
            sub2.cancel();
            sub3.cancel();
          }
        }
      }
    });
  });

  test('detaching all listeners disables the computation graph', () async {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    var callCnt1 = 0;
    var callCnt2 = 0;

    final c1 = Computed(() {
      callCnt1 += 1;
      return source.use;
    });

    final c2 = Computed(() {
      callCnt2 += 1;
      return c1.use * 2;
    });

    var checkCnt = 0;

    var sub = c2.listen((output) {
      checkCnt++;
      expect(output, 0);
    }, (e) => fail(e.toString()));

    expect(callCnt1, 2);
    expect(callCnt2, 2);
    expect(checkCnt, 0);

    try {
      controller.add(0);
      expect(callCnt1, 4);
      expect(callCnt2, 4);
      await Future.value(); // Wait for the listener to fire
      expect(checkCnt, 1);
    } finally {
      sub.cancel();
    }

    controller.add(1); // Must not trigger a re-calculation
    expect(callCnt1, 4);
    expect(callCnt2, 4);
    expect(checkCnt, 1);

    sub = c2.listen((output) {
      expect(output, 4);
      checkCnt++;
    }, (e) => fail(e.toString())); // This triggers a re-computation

    await Future.value();
    expect(callCnt1,
        6); // Attaching the listeners triggers a call to discover dependencies
    expect(callCnt2, 6);
    expect(checkCnt,
        1); // The listener is not run: no value was produced by the stream after the second listen

    controller.add(2); // Must trigger a re-calculation
    expect(callCnt1, 8);
    expect(callCnt2, 8);
    expect(checkCnt, 2);
  });

  test('exceptions raised by computations are propagated', () async {
    var callCnt = 0;
    final c1 = Computed<int>(() {
      callCnt++;
      throw 42;
    });

    final c2 = Computed(() => c1.use);

    var checkFlag = false;

    final sub = c2.listen((output) {
      fail('must not reach here');
    }, (e) {
      checkFlag = true;
      expect(e, 42);
    });

    try {
      await Future.value(); // Await the microtask
      expect(checkFlag, true);
      expect(callCnt,
          1); // The first computation should never be re-run, as it has no dependencies
    } finally {
      sub.cancel();
    }
  });

  test('constant computations work', () async {
    var callCnt = 0;

    final c1 = Computed<int>(() {
      callCnt++;
      return 42;
    });

    var checkFlag = false;

    var sub = c1.listen((event) {
      expect(checkFlag, false);
      checkFlag = true;
      expect(event, 42);
    }, (e) => fail(e.toString()));

    try {
      await Future.value(); // Wait for the update
      expect(checkFlag, true);
      expect(callCnt, 2);
    } finally {
      sub.cancel();
    }

    checkFlag = false;

    sub = c1.listen((event) {
      expect(checkFlag, false);
      checkFlag = true;
      expect(event, 42);
    }, (e) => fail(e.toString()));

    try {
      await Future.value(); // Wait for the update
      expect(checkFlag, true);
      expect(callCnt, 2); // The constant does not get re-computed
    } finally {
      sub.cancel();
    }
  });

  test('detaching all listeners removes the expando', () async {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    final c = Computed(() {
      return source.use;
    });

    var sub = c.listen((output) {}, (e) => fail(e.toString()));

    sub.cancel();

    expect(GlobalCtx.routerFor(source), null);
  });

  test('cannot call use/prev outside computations', () {
    final s = Stream.empty();
    try {
      s.use;
      fail("Should have thrown");
    } on StateError catch (e) {
      expect(e.message,
          "`use` and `prev` are only allowed inside Computed expressions.");
    }

    try {
      s.prev;
      fail("Should have thrown");
    } on StateError catch (e) {
      expect(e.message,
          "`use` and `prev` are only allowed inside Computed expressions.");
    }
  });

  test('asserts on detected side effects', () async {
    var ctr = 0;
    final c = Computed(() => ctr++);

    var flag = false;

    final sub = c.listen((event) {
      fail('Must not call listener');
    }, (e) {
      expect(flag, false);
      flag = true;
      expect(
          e.message,
          contains(
              "Computed expressions must be purely functional. Please use listeners for side effects."));
    });
    try {
      await Future.value();
      expect(flag, true);
    } finally {
      sub.cancel();
    }
  });

  test('asserts if f throws only on the second try', () async {
    var ctr = 0;
    final c = Computed(() {
      if (ctr == 1) throw 42;
      return ctr++;
    });

    var flag = false;

    final sub = c.listen((event) {
      fail('Must not call listener');
    }, (e) {
      expect(flag, false);
      flag = true;
      expect(
          e.message,
          contains(
              "Computed expressions must be purely functional. Please use listeners for side effects."));
    });
    try {
      await Future.value();
      expect(flag, true);
    } finally {
      sub.cancel();
    }
  });

  test('asserts if f throws NVE only on the second try', () async {
    var ctr = 0;
    final c = Computed(() {
      ctr++;
      if (ctr == 1) throw NoValueException();
      return 42;
    });

    var flag = false;

    final sub = c.listen((event) {
      fail('Must not call listener');
    }, (e) {
      expect(flag, false);
      flag = true;
      expect(
          e.message,
          contains(
              "Computed expressions must be purely functional. Please use listeners for side effects."));
    });
    try {
      await Future.value();
      expect(flag, true);
    } finally {
      sub.cancel();
    }
  });

  test(
      '(regression) avoids re-computing deeply nested computations exponentially many times',
      () async {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    var cnt1 = 0, cnt2 = 0, cnt3 = 0;

    final c1 = Computed(() {
      cnt1++;
      source.use;
    });
    final c2 = Computed(() {
      cnt2++;
      c1.use;
    });
    final c3 = Computed(() {
      cnt3++;
      c2.use;
    });

    final sub = c3.listen(null, (e) => fail(e.toString()));

    try {
      expect(cnt1, 2);
      expect(cnt2, 2);
      expect(cnt3, 2);
    } finally {
      sub.cancel();
    }
  });

  group('mocks', () {
    test('fix and unmock works', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      final c = Computed(() {
        return source.use;
      });

      var listenerCallCnt = 0;
      var expectation = 42;

      var sub = c.listen((output) {
        listenerCallCnt++;
        expect(output, expectation);
      }, (e) => fail(e.toString()));

      try {
        c.fix(42);
        expect(listenerCallCnt, 1);
        c.fix(42);
        expect(listenerCallCnt, 1);
        expectation = 43;
        c.fix(43);
        expect(listenerCallCnt, 2);

        controller.add(0);
        // Does not trigger a re-computation, as c has already been fixed
        expect(listenerCallCnt, 2);

        c.unmock();
        // Does not trigger a call of the listener,
        // as the source has not produced any value yet.
        expect(listenerCallCnt, 2);

        expectation = 1;
        controller.add(1);
        expect(listenerCallCnt, 3);
      } finally {
        sub.cancel();
      }
    });

    test('fixThrow works', () async {
      final c1 = Computed(() {
        return 0;
      });

      var callCnt = 0;
      var mustThrow = false;

      final c2 = Computed(() {
        callCnt++;
        if (mustThrow) {
          try {
            c1.use;
            fail('c1 must throw');
          } catch (e) {
            expect(e, 42);
          }
        } else {
          c1.use;
        }
      });

      var sub = c2.listen((output) {}, (e) => fail(e.toString()));

      try {
        mustThrow = true;
        c1.fixThrow(42);
      } finally {
        sub.cancel();
      }

      expect(callCnt, 4);
    });
  });

  test('computations can use and return null', () {
    final controller = StreamController<int?>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    var c1cnt = 0;
    var c2cnt = 0;

    final c1 = Computed(() {
      c1cnt++;
      return source.use;
    });
    final c2 = Computed(() {
      c2cnt++;
      return c1.use;
    });

    var subCnt = 0;
    int? expected;

    final sub = c2.listen((event) {
      subCnt++;
      expect(event, expected);
    }, (e) => fail(e.toString()));

    expect(c1cnt, 2);
    expect(c2cnt, 2);
    expect(subCnt, 0);

    try {
      expected = null;
      controller.add(null);
      expect(c1cnt, 4);
      expect(c2cnt, 4);
      expect(subCnt, 1);
      expected = 0;
      controller.add(0);
      expect(c1cnt, 6);
      expect(c2cnt, 6);
      expect(subCnt, 2);
      expected = null;
      controller.add(null);
      expect(c1cnt, 8);
      expect(c2cnt, 8);
      expect(subCnt, 3);
      controller.add(null);
      expect(c1cnt, 8);
      expect(c2cnt, 8);
      expect(subCnt, 3);
    } finally {
      sub.cancel();
    }
  });

  test('exceptions are memoized', () {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    var c1cnt = 0;
    var c2cnt = 0;

    final c1 = Computed(() {
      c1cnt++;
      if (source.use % 2 == 0) throw source.use % 4;
      return source.use;
    });
    final c2 = Computed(() {
      c2cnt++;
      return c1.use;
    });

    var subCnt = 0;
    bool expectThrow = false;

    final sub = c2.listen((event) {
      subCnt++;
      expect(expectThrow, false);
    }, (e) {
      subCnt++;
      expect(expectThrow, true);
    });

    expect(c1cnt, 2);
    expect(c2cnt, 2);
    expect(subCnt, 0);

    try {
      expectThrow = true;
      controller.add(0);
      expect(c1cnt, 3);
      expect(c2cnt, 3);
      expect(subCnt, 1);
      controller.add(4);
      expect(c1cnt, 4);
      expect(c2cnt, 3);
      expect(subCnt, 1);
      controller.add(2);
      expect(c1cnt, 5);
      expect(c2cnt, 4);
      expect(subCnt, 2);
      expectThrow = false;
      controller.add(1);
      expect(c1cnt, 7);
      expect(c2cnt, 6);
      expect(subCnt, 3);
      expectThrow = true;
      controller.add(0);
      expect(c1cnt, 8);
      expect(c2cnt, 7);
      expect(subCnt, 4);
    } finally {
      sub.cancel();
    }
  });

  test('abandoned dependencies are dropped', () {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    var dependOnSource = true;

    var cnt = 0;

    final c = Computed(() {
      cnt++;
      if (dependOnSource) {
        return source.use;
      } else {
        return 1;
      }
    });

    var subCnt = 0;
    var expectation = 0;

    final sub = c.listen((event) {
      subCnt++;
      expect(event, expectation);
    }, (e) => fail(e.toString()));

    try {
      expect(cnt, 2);
      controller.add(0);
      expect(cnt, 4);
      expect(subCnt, 1);

      dependOnSource = false;
      expectation = 1;
      controller.add(2);
      expect(cnt, 6);
      expect(subCnt, 2);

      // From this point on c is regarded as a constant
      // Thus, adding items to the stream does not trigger a re-computation

      controller.add(3);
      expect(cnt, 6);
      expect(subCnt, 2);
    } finally {
      sub.cancel();
    }
  });

  test('can add new dependencies on subsequent calls', () async {
    final controller1 = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source1 = controller1.stream;

    final controller2 = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source2 = controller2.stream;

    var dependOnSource2 = false;

    var cnt = 0;

    final c = Computed(() {
      cnt++;
      var sum = source1.use;
      if (dependOnSource2) sum += source2.use;
      return sum;
    });

    var subCnt = 0;
    var expectation = 0;

    final sub = c.listen((event) {
      subCnt++;
      expect(event, expectation);
    }, (e) => fail(e.toString()));

    try {
      expect(cnt, 2);
      controller1.add(0);
      expect(cnt, 4);
      expect(subCnt, 1);

      dependOnSource2 = true;
      controller1.add(1);
      expect(cnt,
          6); // Attempted evaluation, failed with NoValueException on source2
      expect(subCnt, 1);

      expectation = 3;
      controller2.add(2);
      expect(cnt, 8);
      expect(subCnt, 2);
    } finally {
      sub.cancel();
    }
  });

  test(
      '(regression) new dependencies computed for the first time do not mark running computation as dirty',
      () async {
    final controller1 = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source1 = controller1.stream;

    final controller2 = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source2 = controller2.stream;

    var dependOnC2 = false;

    final c2 = Computed(() => source1.use);

    final c = Computed(() {
      if (dependOnC2) c2.use;
      return source1.use + source2.use;
    });

    final c3 = Computed(() => c.use);

    var subCnt = 0;
    var expectation = 0;

    final sub = c3.listen((event) {
      subCnt++;
      expect(event, expectation);
    }, (e) => fail(e.toString()));

    try {
      await Future.value();
      expect(subCnt, 0);
      expectation = 3;
      controller1.add(1);
      controller2.add(2);
      await Future.value();
      expect(subCnt, 1);
      dependOnC2 = true;
      expectation = 5;
      controller1.add(3);
      await Future.value();
      expect(subCnt, 2);
    } finally {
      sub.cancel();
    }
  });

  group('prev', () {
    test('works on streams', () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      // Also test that cancelling all the listeners reset all the state
      for (int i = 0; i < 2; i++) {
        int? expectation; // If null, expect NoValueError

        final c = Computed(() {
          try {
            expect(source1.prev, expectation);
          } on NoValueException {
            expect(expectation, null);
          }
          return source1.use;
        });

        var subCnt = 0;

        final sub = c.listen((event) {
          subCnt++;
        }, (e) => fail(e.toString()));

        try {
          expect(subCnt, 0);
          controller1.add(0);
          expect(subCnt, 1);
          expectation = 0;
          controller1.add(1);
          expect(subCnt, 2);
        } finally {
          sub.cancel();
        }
      }
    });

    test('works on streams (bigger)', () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      final controller2 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source2 = controller2.stream;

      int? expectation1; // If null, expect NoValueError
      int? expectation2; // If null, expect NoValueError

      final c = Computed(() {
        try {
          expect(source1.prev, expectation1);
        } on NoValueException {
          expect(expectation1, null);
        }
        try {
          expect(source2.prev, expectation2);
        } on NoValueException {
          expect(expectation2, null);
        }
        return source1.use + source2.use;
      });

      var subCnt = 0;

      final sub = c.listen((event) {
        subCnt++;
      }, (e) => fail(e.toString()));

      try {
        expect(subCnt, 0);
        controller1.add(0);
        expect(subCnt, 0);
        controller2.add(1);
        expect(subCnt, 1);
        expectation1 = 0;
        expectation2 = 1;
        controller1.add(1);
        expect(subCnt, 2);
        expectation1 = 1;
        expectation2 = 1;
        controller1.add(2);
        expect(subCnt, 3);
      } finally {
        sub.cancel();
      }
    });

    test('in computations whose value did not change', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      int? expectation; // If null, expect NoValueError

      final c = Computed(() {
        source.use; // Make sure to subscribe to it
        try {
          expect(source.prev, expectation);
        } on NoValueException {
          expect(expectation, null);
        }
        return source.use * source.use;
      });

      var subCnt = 0;

      final sub = c.listen((event) {
        subCnt++;
      }, (e) => fail(e.toString()));

      try {
        expect(subCnt, 0);
        controller.add(0);
        expect(subCnt, 1);
        expectation = 0;
        controller.add(1);
        expect(subCnt, 2);
        expectation = 1;
        controller.add(-1); // Note that (-1)^2 == 1^2
        expect(subCnt, 2);
        // Note that expectation == 1, as the -1 case did not lead to a change in the result
        controller.add(1);
        expect(subCnt, 2);
        controller.add(-1); // Note that (-1)^2 == 1^2
        expect(subCnt, 2);
        controller.add(0);
        expect(subCnt, 3);
      } finally {
        sub.cancel();
      }
    });

    test('works on computations', () {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      int? expectation; // If null, expect NoValueError

      final c = Computed(() {
        return source.use * source.use;
      });

      final c2 = Computed(() {
        try {
          expect(c.prev, expectation);
        } on NoValueException {
          expect(expectation, null);
        }
        return c.use;
      });

      var subCnt = 0;

      final sub = c2.listen((event) {
        subCnt++;
      }, (e) => fail(e.toString()));

      try {
        controller.add(0);
        expect(subCnt, 1);
        expectation = 0;
        controller.add(1);
        expect(subCnt, 2);
        controller.add(-1); // (-1)^2 == 1^2
        expect(subCnt, 2);
        expectation = 1; // And not -1
        controller.add(2);
        expect(subCnt, 3);
      } finally {
        sub.cancel();
      }
    });

    test('computation self .prev works', () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      int? expectation; // If null, expect NoValueError

      late Computed<int> c;

      c = Computed(() {
        source1.use;
        try {
          expect(c.prev, expectation);
        } on NoValueException {
          expect(expectation, null);
        }
        return source1.use;
      });

      var subCnt = 0;

      final sub = c.listen((event) {
        subCnt++;
      }, (e) => fail(e.toString()));

      try {
        await Future.value();
        expect(subCnt, 0);
        controller1.add(0);
        expect(subCnt, 1);
        expectation = 0;
        controller1.add(1);
        expect(subCnt, 2);
      } finally {
        sub.cancel();
      }
    });

    test('computation withPrev works', () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      for (var useSelfPrev in [false, true]) {
        int prevExpectation = 0;

        late Computed<int> c;

        c = Computed.withPrev((prev) {
          expect(useSelfPrev ? c.prev : prev, prevExpectation);
          return source1.use;
        }, initialPrev: 0);

        var subCnt = 0;

        final sub = c.listen((event) {
          subCnt++;
        }, (e) => fail(e.toString()));

        try {
          await Future.value();
          expect(subCnt, 0);
          controller1.add(1);
          expect(subCnt, 1);
          prevExpectation = 1;
          controller1.add(2);
          expect(subCnt, 2);
        } finally {
          sub.cancel();
        }
      }
    });

    test('throws for data sources which threw during the last computation',
        () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      bool expectError = false;
      int? valueExpectation;
      Matcher? errorMatcher;

      var subCnt = 0;

      final c = Computed(() {
        try {
          source1.use; // Subscribe to it
        } on NoValueException {
          rethrow;
        } catch (e) {
          // Swallow, we are testing [prev] behaviour
        }
        try {
          final res = source1.prev;
          expect(expectError, false);
          expect(res, valueExpectation);
        } catch (e) {
          // Note that this also catches NoValueException, that is intended
          expect(expectError, true);
          expect(e, errorMatcher);
        }
        return subCnt; // To keep the listener call from being memoized away
      });

      final sub = c.listen((event) {
        subCnt++;
      }, (e) => fail(e.toString()));

      try {
        expect(subCnt, 0);
        expectError = true;
        errorMatcher = isA<NoValueException>();
        controller1.add(0);
        expect(subCnt, 1);
        expectError = false;
        valueExpectation = 0;
        controller1.addError(1);
        expect(subCnt, 2);
        expectError = true;
        errorMatcher = equals(1);
        controller1.add(2);
        expect(subCnt, 3);
      } finally {
        sub.cancel();
      }
    });

    test(
        'throws for data sources which did not have a value during the last computation',
        () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      bool expectError = false;
      int? valueExpectation;
      Matcher? errorMatcher;

      var subCnt = 0;

      final c = Computed(() {
        try {
          source1.use; // Subscribe to it
        } on NoValueException {
          // Swallow
        }
        try {
          final res = source1.prev;
          expect(expectError, false);
          expect(res, valueExpectation);
        } catch (e) {
          // Note that this also catches NoValueException, that is intended
          expect(expectError, true);
          expect(e, errorMatcher);
        }
        return subCnt; // To keep the listener call from being memoized away
      });

      expectError = true;
      errorMatcher = isA<NoValueException>();

      final sub = c.listen((event) {
        subCnt++;
      }, (e) => fail(e.toString()));

      try {
        await Future.value();
        expect(subCnt, 1);
        controller1.add(0);
        expect(subCnt, 2);
        expectError = false;
        valueExpectation = 0;
        controller1.add(1);
        expect(subCnt, 3);
      } finally {
        sub.cancel();
      }
    });

    test(
        'throws for data sources not subscribed to during the previous computation',
        () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      final controller2 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source2 = controller2.stream;

      int? expectation1; // If null, expect NoValueError
      int? expectation2; // If null, expect NoValueError

      var use2 = false;

      final c = Computed(() {
        try {
          expect(source1.prev, expectation1);
        } on NoValueException {
          expect(expectation1, null);
        }
        try {
          expect(source2.prev, expectation2);
        } on NoValueException {
          expect(expectation2, null);
        }
        return source1.use + (use2 ? source2.use : 0);
      });

      var subCnt = 0;

      final sub = c.listen((event) {
        subCnt++;
      }, (e) => fail(e.toString()));

      try {
        controller1.add(0);
        expect(subCnt, 1);
        expectation1 = 0;
        controller1.add(1);
        expect(subCnt, 2);
        controller2.add(1);
        expect(subCnt,
            2); // Does not trigger a re-computation as c has not yet used source2
        expectation1 = 1;
        // Note that expectation2 is still null
        controller1.add(2);
        expect(subCnt, 3);
        use2 = true;
        expectation1 = 2;
        // Note that expectation2 is still null
        controller1.add(3);
        expect(subCnt, 3); // Throws NoValueException on source2
        // Note that expectation1 did not change: the previous run did not produce a result
        // And expectation2 is still null
        controller2.add(4);
        expect(subCnt, 4);
        expectation1 = 3;
        expectation2 = 4;
        controller2.add(5);
        expect(subCnt, 5);
      } finally {
        sub.cancel();
      }
    });
  });

  group('cycles', () {
    test('computation self.use throws', () async {
      var flag = false;
      late Computed<void> c;
      c = Computed(() {
        try {
          c.use;
          fail('Must have thrown');
        } on CyclicUseException {
          flag = true;
        }
      });

      final sub = c.listen((event) {}, (e) => fail(e.toString()));

      try {
        expect(flag, true);
      } finally {
        sub.cancel();
      }
    });

    test(
        'cyclic dependency during initial computation throws CyclicUseException',
        () async {
      late Computed<int> b;
      final a = Computed(() => b.use);
      b = Computed(() => a.use);

      var flag = false;

      final sub = b.listen((event) {
        fail('What?');
      }, (e) {
        flag = true;
        expect(e, isA<CyclicUseException>());
      });

      try {
        await Future.value();
        expect(flag, true);
      } finally {
        sub.cancel();
      }
    });

    test('update computation cyclic dependency', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a sync controller to make debugging easier
      final source = controller.stream;

      var createCycle = false;

      late Computed<int> b;
      final a = Computed(() => createCycle ? b.use : 0 + source.use);

      var cnt1 = 0;
      var cnt2 = 0;

      b = Computed(() => a.use);

      final sub = b.listen((event) {
        cnt1++;
        expect(event, 1);
      }, (e) {
        expect(e, isA<CyclicUseException>());
        cnt2++;
      });

      try {
        controller.add(1);

        expect(cnt1, 1);
        expect(cnt2, 0);

        createCycle = true;
        controller.add(2);

        expect(cnt1, 1);
        expect(cnt2, 1);
      } finally {
        sub.cancel();
      }
    });
  });
}
