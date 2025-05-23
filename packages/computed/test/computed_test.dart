import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/src/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:test/test.dart';

void main() {
  test('unlistened computations are not computed', () {
    Computed(() => fail('must not be computed'));
  });

  test('shorthand notation works', () async {
    final x = $(() => 42);
    var flag = false;
    x.listen((event) {
      expect(flag, false);
      flag = true;
      expect(event, 42);
    }, (e) => fail(e.toString()));
    await Future.value();
    expect(flag, true);
  });

  test('effect works', () async {
    final s = ValueStream(sync: true);
    s.add(42);
    int flag = 0;

    final c = $(() => s.use);
    final effect = Computed.effect(() => flag = c.use);

    await Future.value();

    expect(flag, 42);
    s.add(43);
    expect(flag, 43);

    effect.cancel();
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

      controller.add(0);
      expect(lastRes, 0);
      controller.add(1);
      expect(lastRes, 2);

      sub.cancel();
    });

    test('(regression) .use gracefully handles sync exceptions while listening',
        () async {
      final s = StreamController<int>();
      final stream = s.stream;
      stream.listen((event) {}).cancel(); // The stream is not usable anymore
      final c = $(() => stream.use);
      var cnt = 0;

      void valueListener(int event) => fail('must not produce a value');
      void errorListener(Object e) {
        expect(e, isA<StateError>());
        expect(
            (e as StateError).message, 'Stream has already been listened to.');
        cnt++;
      }

      var sub = c.listen(valueListener, errorListener);
      expect(cnt, 0);
      await Future.value();
      expect(cnt, 1);

      sub.cancel();

      await Future.value();
      expect(cnt, 1); // Must not be called again

      sub = c.listen(valueListener, errorListener);

      expect(cnt, 1);
      await Future.value();
      expect(cnt, 2);

      sub.cancel();
    });

    test('useOr works', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      var lCnt = 0;
      int? lastRes;

      final sub = Computed(() => source.useOr(21) * 2).listen((event) {
        lCnt++;
        lastRes = event;
      }, (e) => fail(e.toString()));

      expect(lCnt, 0);
      await Future.value();
      expect(lCnt, 1);
      expect(lastRes, 42);

      controller.add(0);
      expect(lCnt, 2);
      expect(lastRes, 0);

      sub.cancel();
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
              if (reactFirst) source.react((p0) {});
              source.use;
            }
            int? reactRes;
            source.react((val) => reactRes = val);
            return reactRes != null ? (reactRes! * 2) : null;
          }).listen((event) {
            lCnt++;
            lastRes = event;
          }, (e) => fail(e.toString()));

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

          sub.cancel();
        }
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

      final s = ValueStream.seeded(42, sync: true);
      final c2 = Computed(() => s.use);

      final c = Computed(() {
        // Subscribe to both sources and c2
        cCnt++;
        c2.use;
        var flag = false;
        source1.react((val) {
          flag = true;
          expect(val, expectation1);
        });
        if (!flag) expect(expectation1, null);
        flag = false;
        source2.react((val) {
          flag = true;
          expect(val, expectation2);
        });
        if (!flag) expect(expectation2, null);
      });

      final sub = c.listen(null, (e) => fail(e.toString()));

      expect(cCnt, 2);
      await Future.value(); // Await for Computed to subscribe to [s]
      expect(cCnt, 4);

      expectation1 = 0;
      controller1.add(0);
      expect(cCnt, 6);
      controller1.add(0);
      expect(cCnt, 8);
      expectation1 = null;
      expectation2 = 1;
      controller2.add(1);
      expect(cCnt, 10);
      controller2.add(1);
      expect(cCnt, 12);
      expectation2 = 2;
      controller2.add(2);
      expect(cCnt, 14);
      expectation1 = 2;
      expectation2 = null;
      controller1.add(2);
      expect(cCnt, 16);
      expectation1 = null;
      s.add(43);
      expect(cCnt, 18);

      sub.cancel();
    });

    test('.react propagates error stack traces', () async {
      final s = StreamController.broadcast(sync: true);
      final stream = s.stream;
      var cnt = 0;
      Object? e;
      StackTrace? st;
      final c = $(() {
        stream.react((p0) => fail('Must not be called'), (e_, st_) {
          cnt++;
          e = e_;
          st = st_;
        });
      });
      final sub = c.listen(null);
      await Future.value();
      await Future.value();
      expect(cnt, 0);
      final myST = StackTrace.current;
      s.addError(1, myST);
      expect(cnt, 2);
      expect(e, 1);
      expect(st, same(myST));
      sub.cancel();
    });

    test('.react rejects invalid onError', () async {
      final s = StreamController.broadcast(sync: true);
      final stream = s.stream;
      final c = $(() =>
          stream.react((p0) => fail('Must not be called'), (a, b, c) => null));
      var cnt = 0;
      Object? e;
      final sub = c.listen((event) => fail('Must not be called'), (e_) {
        cnt++;
        e = e_;
      });
      await Future.value();
      expect(cnt, 1);
      expect(e, isA<ArgumentError>());
      expect((e as ArgumentError).name, 'onError');
      expect((e as ArgumentError).message,
          'onError must accept one Object or one Object and a StackTrace as arguments');
      sub.cancel();
    });

    test('(regression) can subscribe to constant computations', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      var cCnt = 0;

      final c2 = Computed(() => 42);

      int? expectation; // If null, expect NoValueException

      final c = Computed(() {
        cCnt++;
        // Subscribe to the sources and c2
        expect(c2.use, 42);
        try {
          expect(source.use, expectation);
        } on NoValueException {
          expect(expectation, null);
        }
      });

      final sub = c.listen(null, (e) => fail(e.toString()));

      expect(cCnt, 2);
      expectation = 0;
      controller.add(0);
      expect(cCnt, 4);
      controller.add(0);
      expect(cCnt, 4);
      expectation = 1;
      controller.add(1);
      expect(cCnt, 6);
      controller.add(1);
      expect(cCnt, 6);
      expectation = 2;
      controller.add(2);
      expect(cCnt, 8);

      sub.cancel();
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

        sub.cancel();

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

      sub.cancel();
    });

    test('unwrap works', () async {
      final innerStreams = <StreamController<int>>[];
      Stream<int> streamFor(int value) {
        final stream = StreamController<int>();
        stream.add(value);
        stream.add(value + 1);
        innerStreams.add(stream);
        return stream.stream;
      }

      final controller = StreamController<int>(sync: true);
      final outerStream = controller.stream;

      var cCnt = 0;

      final c = Computed.async(() {
        cCnt++;
        return streamFor(outerStream.use);
      }).unwrap;

      var lCnt = 0;
      int? lastRes;

      final sub = c.listen((event) {
        lCnt++;
        lastRes = event;
      }, (e) => fail(e.toString()));

      expect(cCnt, 1);
      await Future.value();
      expect(cCnt, 1);
      expect(lCnt, 0);

      controller.add(0);
      expect(innerStreams.length, 1);
      expect(cCnt, 2);
      expect(lCnt, 0);
      await Future.value();
      expect(cCnt, 2);
      expect(lCnt, 1);
      expect(lastRes, 0);
      for (var i = 0; i < 2; i++) {
        await Future.value();
        expect(cCnt, 2);
        expect(lCnt, 2);
        expect(lastRes, 1);
      }

      controller.add(2);
      expect(innerStreams.length, 2);
      expect(innerStreams[0].hasListener, false);
      expect(cCnt, 3);
      expect(lCnt, 2);
      await Future.value();
      expect(cCnt, 3);
      expect(lCnt, 3);
      expect(lastRes, 2);
      for (var i = 0; i < 2; i++) {
        await Future.value();
        expect(cCnt, 3);
        expect(lCnt, 4);
        expect(lastRes, 3);
      }

      sub.cancel();

      expect(innerStreams.length, 2);
      expect(innerStreams[1].hasListener, false);
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

      completer.complete(2);
      await Future.value();
      expect(callCnt, 1);

      sub.cancel();
    });

    test('useOr works', () async {
      final completer = Completer<int>();
      final future = completer.future;

      final x = Computed(() => future.useOr(42));

      var callCnt = 0;
      int? lastEvent;

      final sub = x.listen((event) {
        callCnt++;
        lastEvent = event;
      }, (e) => fail(e.toString()));

      expect(callCnt, 0);
      await Future.value();
      expect(callCnt, 1);
      expect(lastEvent, 42);

      completer.complete(1);
      await Future.value();
      expect(callCnt, 2);
      expect(lastEvent, 1);

      sub.cancel();
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

      completer.completeError(1);
      await Future.value(0);
      expect(callCnt, 1);

      sub.cancel();
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

    test('unwrap works', () async {
      final controller = StreamController<int>(sync: true);
      final stream = controller.stream;

      var cCnt = 0;

      final c = Computed.async(() {
        cCnt++;
        final val = stream.use;
        return Future.microtask(() => val);
      }).unwrap;

      var lCnt = 0;
      int? lastRes;

      final sub = c.listen((event) {
        lCnt++;
        lastRes = event;
      }, (e) => fail(e.toString()));

      expect(cCnt, 1);
      await Future.value();
      expect(cCnt, 1);
      expect(lCnt, 0);

      controller.add(0);
      expect(cCnt, 2);
      expect(lCnt, 0);
      for (var i = 0; i < 2; i++) {
        await Future.value();
        expect(cCnt, 2);
        expect(lCnt, 1);
        expect(lastRes, 0);
      }

      controller.add(1);
      expect(cCnt, 3);
      expect(lCnt, 1);
      for (var i = 0; i < 2; i++) {
        await Future.value();
        expect(cCnt, 3);
        expect(lCnt, 2);
        expect(lastRes, 1);
      }

      sub.cancel();
    });
  });

  test('listen invokes handleUncaughtError if needed', () async {
    var ueCount = 0;
    Object? lastError;
    void hUE(Zone self, ZoneDelegate parent, Zone zone, Object error,
        StackTrace stackTrace) {
      expect(stackTrace.toString(), contains('myThrower'));
      ueCount++;
      lastError = error;
    }

    void myThrower(int toThrow) => throw toThrow;

    final s = ValueStream(sync: true);
    s.add(0);

    final c = $(() => myThrower(s.useOr(42)));
    final zone = Zone.current
        .fork(specification: ZoneSpecification(handleUncaughtError: hUE));
    final sub1 = zone.run(() => c.listen((event) {}, null));
    expect(ueCount, 1);
    expect(lastError, 42);
    await Future.value();
    expect(ueCount, 2);
    expect(lastError, 0);

    s.add(1);
    expect(ueCount, 3);
    expect(lastError, 1);

    final sub2 = zone.run(() => c.listen((event) {}, null));

    final sub3 = zone.run(() => c.listen((event) {}, (err) {}));

    s.add(2);
    expect(ueCount, 3);

    sub3.cancel();

    s.add(3);
    expect(ueCount, 4);
    expect(lastError, 3);

    sub1.cancel();
    sub2.cancel();
  });

  test('listen propagates stack traces', () async {
    final s = ValueStream<int>(sync: true);
    final x = $(() {
      void myTag() {
        throw s.useOr(42);
      }

      myTag();
    });
    var cnt = 0;
    Object? e;
    StackTrace? st;
    x.listen((event) => fail('Must not be called'), (e_, st_) {
      cnt++;
      e = e_;
      st = st_;
    });
    await Future.value();
    expect(cnt, 1);
    expect(e, 42);
    expect(st.toString(), contains('myTag'));
    s.add(1);
    expect(cnt, 2);
    expect(e, 1);
    expect(st.toString(), contains('myTag'));
  });

  test('listen rejects invalid onError', () async {
    final x = $(() => 0);
    void checkThrows(void Function() f) {
      try {
        f();
      } catch (e) {
        expect(e, isA<ArgumentError>());
        expect((e as ArgumentError).name, 'onError');
        expect(e.message,
            'onError must accept one Object or one Object and a StackTrace as arguments');
        return;
      }
      fail('Must have throwns');
    }

    checkThrows(() => x.listen(null, (a, b, c) => null));
    final sub = x.listen(null, null);
    checkThrows(() => sub.onError((a, b, c) => null));
    sub.cancel();
  });

  test('(regression) listeners can cancel themselves', () async {
    final s = ValueStream.seeded(0, sync: true);
    final c = $(() => s.use);
    var cCnt = 0;
    late final ComputedSubscription<void> sub;
    sub = c.listen((_) {
      cCnt++;
      if (cCnt == 2) {
        sub.cancel();
      }
    }, null);
    await Future.value();
    expect(cCnt, 1);
    s.add(1);
    expect(cCnt, 2);
    s.add(2);
    // The listener has been cancelled
    expect(cCnt, 2);
  });

  test(
      '(regression) listeners can cancel other listeners on the same computation',
      () async {
    final s = ValueStream.seeded(0, sync: true);
    final c = $(() => s.use);
    var cnt1 = 0, cnt2 = 0, cnt3 = 0;
    final sub1 = c.listen((_) {
      cnt1++;
    }, null);
    late final ComputedSubscription<int> sub3;
    final sub2 = c.listen((_) {
      cnt2++;
      if (cnt2 == 2) {
        sub1.cancel();
        sub3.cancel();
      }
    }, null);
    sub3 = c.listen((_) {
      cnt3++;
    }, null);
    await Future.value();
    expect(cnt1, 1);
    expect(cnt2, 1);
    expect(cnt3, 1);
    s.add(1);
    expect(cnt1, 2);
    expect(cnt2, 2);
    expect(cnt3, 1); // Got cancelled by sub2
    s.add(2);
    expect(cnt1, 2); // Got cancelled by sub2
    expect(cnt2, 3);
    expect(cnt3, 1);

    sub2.cancel();
  });

  test(
      'does not invoke handleUncaughtError if there are downstream computations',
      () async {
    final s = ValueStream(sync: true);
    s.add(0);

    final c = $(() => throw s.useOr(42));
    final c2 = $(() {
      try {
        c.use;
      } catch (e) {
        // pass
      }
    });
    final sub3 = c2.listen((event) {}, null);
    final sub1 = c.listen((event) {}, null);
    await Future.value();

    s.add(1);

    final sub2 = c.listen((event) {}, (err) {});

    s.add(2);

    sub2.cancel();

    s.add(3);

    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
  });

  test('computation listeners can be changed', () {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    final c = Computed(() => source.use);

    final sub = c.listen((event) {
      fail("Must not run");
    }, (e) => fail("Must not run"));

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

    sub.cancel();
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

    controller.add(0);
    expect(lastRes, 1);
    controller.add(1);
    expect(lastRes, 3);

    sub.cancel();
  });

  test('useOr works on computations', () async {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    int? lastRes;

    final x2 = Computed(() => source.use * 2);

    var lCnt = 0;

    final sub = Computed(() => x2.useOr(41) + 1).listen((event) {
      lCnt++;
      lastRes = event;
    }, (e) => fail(e.toString()));

    expect(lCnt, 0);
    await Future.value();
    expect(lCnt, 1);
    expect(lastRes, 42);

    controller.add(0);
    expect(lCnt, 2);
    expect(lastRes, 1);

    sub.cancel();
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

    sub.cancel();
  });

  test(
      'memoized computations\' results\' identity does not change on equal values',
      () async {
    // Wrap the int in a record so that we can reason about its identity
    final s = ValueStream<((int,), (int,))>.seeded(((0,), (0,)), sync: true);
    final c1 = $(() => s.use.$1);
    final c2 = $(() => s.use.$2);

    var callCnt = 0;

    final sub = Computed(() {
      callCnt += 1;
      switch (callCnt) {
        case 1:
          expect(c1.useOr((42,)), (42,));
          expect(c2.useOr((42,)), (42,));
        case 2:
          expect(c1.use, (0,));
          expect(c2.use, (0,));
        case 3:
          expect(c1.use, (0,));
          expect(c2.use, (1,));
          // This is what we are really testing
          expect(c1.prev, same(c1.use));
        case _:
          fail('Must not happen');
      }

      return;
    }, assertIdempotent: false)
        .listen(null);

    await Future.value();
    expect(callCnt, 2);

    s.add(((0,), (0,)));
    expect(callCnt, 2); // Does not lead to a re-computation as (0,) == (0,)

    s.add(((0,), (1,))); // This will lead to a re-computation
    expect(callCnt, 3);

    sub.cancel();
  });

  test(
      '.use-ing a computation multiple times doesn\'t run it more times than needed',
      () async {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    for (var hasInitialValue in [false, true]) {
      var cnt = 0;

      final c = Computed(() {
        cnt++;
        return hasInitialValue ? 42 : source.use;
      });
      final c2 = Computed(() => c.use + c.use);

      final sub = c2.listen((event) {}, (e) => fail(e.toString()));

      expect(cnt, 2);
      await Future.value();
      expect(cnt, 2);
      if (!hasInitialValue) {
        controller.add(0);
        expect(cnt, 4);
        controller.add(0);
        expect(cnt, 4);
        controller.add(1);
        expect(cnt, 6);
      }

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

    sub.cancel();
  });

  test('computations can use others via .asStream', () async {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    final queryStream = Computed(() => source.use)
        .asStream
        .map((key) => Future.microtask(() => key));

    var cCnt = 0;

    final result = $(() {
      cCnt++;
      return queryStream.use.use;
    });

    var expectation = 0;
    var callCnt = 0;

    final sub = result.listen((event) {
      callCnt++;
      expect(event, expectation);
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(cCnt, 2);
    expect(callCnt, 0);

    controller.add(0);

    expect(cCnt, 2);

    await Future.value(); // For the asStream to propagate the result

    expect(cCnt, 4);
    expect(callCnt, 0);

    await Future.value(); // For the "query" to complete

    expect(cCnt, 6);
    expect(callCnt, 1);

    controller.add(0);

    await Future.value();
    await Future.value();

    expect(cCnt, 6); // First computation terminates propagation
    expect(callCnt, 1);

    expectation = 1;
    controller.add(1);

    await Future.value(); // For the asStream to propagate the result

    expect(cCnt, 8);
    expect(callCnt, 1);

    await Future.value(); // For the "query" to complete

    expect(cCnt, 10);
    expect(callCnt, 2);

    sub.cancel();
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

        controller.add(0);
        expect(outputs, orderedEquals([0]));
        controller.add(1);
        expect(outputs, orderedEquals([0, 3]));

        sub.cancel();
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

          controller1.add(0);
          expect(outputs2, orderedEquals([]));
          expect(outputs3, orderedEquals([]));
          controller2.add(1);
          expect(outputs2, orderedEquals([1]));
          expect(outputs3, orderedEquals([2]));
          controller1.add(2);
          expect(outputs2, orderedEquals([1, 5]));
          expect(outputs3, orderedEquals([2, 4]));

          sub2.cancel();
          sub3.cancel();
        }
      }
    });

    test('regression test on topological sort', () {
      final co = StreamController(sync: true);
      final stream = co.stream;
      final calls = [];
      final a = $(() {
        calls.add(0);
        return stream.use;
      });
      final b = $(() {
        calls.add(1);
        return a.use;
      });
      final c = $(() {
        calls.add(2);
        return b.use;
      });
      final d = $(() {
        calls.add(3);
        c.use;
        a.use;
      });
      final sub = d.listen(null, null);
      expect(calls, [3, 2, 1, 0, 0, 1, 2, 3]);

      for (var i = 0; i < 5; i++) {
        calls.clear();
        co.add(i);
        expect(calls, [0, 0, 1, 1, 2, 2, 3, 3]);
      }

      sub.cancel();
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

    controller.add(0);
    expect(callCnt1, 4);
    expect(callCnt2, 4);
    await Future.value(); // Wait for the listener to fire
    expect(checkCnt, 1);

    sub.cancel();

    expect(controller.hasListener, false);

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

    sub.cancel();

    expect(controller.hasListener, false);
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

    await Future.value(); // Await the microtask
    expect(checkFlag, true);
    expect(callCnt,
        1); // The first computation should never be re-run, as it has no dependencies

    sub.cancel();
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

    await Future.value(); // Wait for the update
    expect(checkFlag, true);
    expect(callCnt, 2);

    sub.cancel();

    checkFlag = false;

    sub = c1.listen((event) {
      expect(checkFlag, false);
      checkFlag = true;
      expect(event, 42);
    }, (e) => fail(e.toString()));

    expect(callCnt, 4); // Gets re-computed
    await Future.value(); // Wait for the update
    expect(checkFlag, true);
    expect(callCnt, 4);

    sub.cancel();
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
          "`use`, `useWeak`, `react` and `prev` are only allowed inside computations.");
    }

    try {
      s.prev;
      fail("Should have thrown");
    } on StateError catch (e) {
      expect(e.message,
          "`use`, `useWeak`, `react` and `prev` are only allowed inside computations.");
    }
  });

  test('cannot call listen inside computations', () async {
    final c = Computed(() => null);
    final c2 = Computed(() => c.listen((event) {}, null));

    var flag = false;

    final sub = c2.listen((event) {
      fail("Should not call the listener");
    }, (e) {
      expect(flag, false);
      flag = true;
      expect(e, isA<ComputedAsyncError>());
    });

    await Future.value();

    expect(flag, true);

    sub.cancel();
  });

  group('useWeak', () {
    test('does not trigger computation', () async {
      final c = $(() => fail('must not be called'));
      var flag = false;
      final sub = $(() => c.useWeak)
          .listen((e) => fail('must not call the listener'), (e) {
        expect(flag, false);
        expect(e, isA<NoStrongUserException>());
        flag = true;
      });

      expect(flag, false);
      await Future.value();
      expect(flag, true);

      sub.cancel();
    });
    test('subscribes to the result of the computation', () async {
      final s = StreamController(sync: true);
      final stream = s.stream;
      final c = $(() => stream.use);
      final c2 = $(() => c.useWeak);

      final sub1 = c.listen(null, null);
      var lCnt = 0;
      final sub2 = c2.listen((event) {
        lCnt++;
      }, null);

      expect(lCnt, 0);
      s.add(0);
      expect(lCnt, 1);
      s.add(1);
      expect(lCnt, 2);

      sub1.cancel();
      sub2.cancel();
    });
    test('cannot be used outside a computation', () {
      try {
        $(() {}).useWeak;
        fail("Should have thrown");
      } on StateError catch (e) {
        expect(e.message,
            "`use`, `useWeak`, `react` and `prev` are only allowed inside computations.");
      }
    });
    test('does not override use', () async {
      final s = ValueStream.seeded(42, sync: true);
      final c = $(() => s.use);
      final c2 = $(() {
        try {
          c.useWeak;
        } on NoStrongUserException {
          // pass
        }
        return c.use;
      });
      var lCnt = 0;
      int? lastValue;
      var sub = c2.listen((event) {
        lCnt++;
        lastValue = event;
      }, null);

      expect(lCnt, 0);
      await Future.value();
      expect(lCnt, 1);
      expect(lastValue, 42);

      sub.cancel();

      final c3 = $(() {
        c.use;
        return c.useWeak;
      });
      sub = c3.listen((event) {
        lCnt++;
        lastValue = event;
      }, null);

      expect(lCnt, 1);
      await Future.value();
      expect(lCnt, 2);
      expect(lastValue, 42);

      s.add(43);
      expect(lCnt, 3);
      expect(lastValue, 43);

      sub.cancel();
    });
    test('propagates exceptions', () {
      final c = $(() => throw FormatException());
      final c2 = $(() {
        try {
          c.useWeak;
        } on FormatException {
          // pass
        } on NoStrongUserException {
          // pass
        }
      });
      final sub1 = c2.listen(null, null);
      final sub2 = c.listen(null, null); // Must not report an uncaught error
      sub1.cancel();
      sub2.cancel();
    });

    test('does not recompute the user if upstream gains listeners', () async {
      final s = ValueStream<int>.seeded(1, sync: true);
      final suser = $(() => s.use); // To keep Computed subscribed to [s]
      final sub3 = suser.listen(null);
      await Future.value(); // Wait for Computed to subscribe to [s]
      final c1 = $(() => s.use);
      var cnt = 0;
      final c2 = $(() {
        cnt++;
        try {
          return c1.useWeak;
        } on NoStrongUserException {
          return 42;
        }
      });
      final sub1 = c2.listen(null);
      expect(cnt, 2);
      final sub2 = c1.listen(null);
      await Future.value();
      await Future.value();
      expect(cnt, 2);
      s.add(0);
      expect(cnt, 4);

      sub1.cancel();
      sub2.cancel();
      sub3.cancel();
    });

    test('recomputes the user if upstream loses all strong listeners',
        () async {
      final c1 = $(() => 42);
      var cnt = 0;
      final c2 = $(() {
        cnt++;
        try {
          return c1.useWeak;
        } on NoStrongUserException {
          // pass
        }
      });
      final sub2 = c1.listen(null);
      final sub1 = c2.listen(null);
      expect(cnt, 2);
      sub2.cancel();
      expect(cnt, 2);
      await Future.value();
      expect(cnt, 4);

      sub1.cancel();
    });

    test(
        'users using each other are recomputed in a topologically consistent order if upstream loses all strong listeners',
        () async {
      // Test both directions (c2 depending on c3 and vica versa)
      // to really make sure the evaluation order is topologically consistent
      for (var direction in [false, true]) {
        final c1 = $(() => 42);
        var cnt = [];
        late final Computed<void> c3;
        final c2 = $(() {
          cnt.add(2);
          try {
            c1.useWeak;
          } on NoStrongUserException {
            // pass
          }
          if (direction) c3.use;
        });
        c3 = $(() {
          cnt.add(3);
          try {
            c1.useWeak;
          } on NoStrongUserException {
            // pass
          }
          if (!direction) c2.use;
        });
        final sub1 = c1.listen(null);
        final sub2 = c2.listen(null);
        final sub3 = c3.listen(null);
        expect(
            cnt,
            direction
                ? [2, 3, 3, 2]
                : [2, 2, 3, 3]); // Mind the idempotency-check computations
        sub1.cancel();
        expect(cnt, hasLength(4)); // No re-computations
        cnt.clear();
        await Future.value();
        expect(cnt, direction ? [3, 3, 2, 2] : [2, 2, 3, 3]);

        sub2.cancel();
        sub3.cancel();
      }
    });

    test(
        'does not recompute the user if upstream loses all strong listeners but downstream has lost all its listeners since',
        () async {
      final c1 = $(() => 42);
      var cnt = 0;
      final c2 = $(() {
        cnt++;
        try {
          return c1.useWeak;
        } on NoStrongUserException {
          // pass
        }
      });
      final sub2 = c1.listen(null);
      final sub1 = c2.listen(null);
      expect(cnt, 2);
      sub2.cancel();
      sub1.cancel();
      expect(cnt, 2);
      await Future.value();
      expect(cnt, 2); // And not 4
    });

    test(
        'does not recompute the user if upstream loses all strong listeners but downstream has been re-computed since',
        () async {
      final s = ValueStream<int>(sync: true);
      final c1 = $(() => 42);
      var cnt = 0;
      final c2 = $(() {
        cnt++;
        s.useOr(0);
        try {
          return c1.useWeak;
        } on NoStrongUserException {
          // pass
        }
      });
      final sub2 = c1.listen(null);
      final sub1 = c2.listen(null);
      expect(cnt, 2);
      sub2.cancel();
      expect(cnt, 2);
      s.add(0);
      expect(cnt, 4);
      await Future.value();
      expect(cnt, 4); // And not 6

      sub1.cancel();
    });
  });

  group('react', () {
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

      var lCnt = 0; // To prevent memoization of [c]

      final c = Computed(() {
        cnt++;
        useUse ? source.use : source.react((p0) {});
        return lCnt;
      });

      final sub = c.listen((res) {
        lCnt++;
      }, (e) => fail(e.toString()));

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

      sub.cancel();
    });
    test('cannot call use/react inside react callbacks', () async {
      final controller = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream;

      final source2 = Stream.empty();

      final c2 = Computed(() => null);

      for (var f in [
        (p0) => source2.use,
        (p0) => c2.use,
        (p0) => source2.react((p0) {})
      ]) {
        var c = Computed(() {
          source.react(f);
        });

        var expectThrow = false;
        var cnt = 0;

        final sub = c.listen((output) {
          if (expectThrow) {
            fail("Should have thrown");
          } else {
            expect(output, null);
            expectThrow = true;
          }
        }, (e) {
          expect(expectThrow, true);
          cnt++;
          expect(
              e,
              allOf(
                  isA<StateError>(),
                  (StateError e) =>
                      e.message ==
                      "`use`, `useWeak` and `react` not allowed inside react callbacks."));
        });

        await Future.value();
        expect(expectThrow, true);

        controller.add(0);
        await Future.value();
        expect(cnt, 1);

        sub.cancel();
      }
    });
    test('.react onError works', () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      var expectError = false;
      var expectation = 0;
      var cCnt = 0;

      final c = Computed(() {
        cCnt++;
        source1.react((p0) {
          expect(expectError, false);
          expect(p0, expectation);
        }, (p0) {
          expect(expectError, true);
          expect(p0, expectation);
        });
      });

      final sub = c.listen(null, (e) => fail(e.toString()));

      expect(cCnt, 2);
      controller1.add(0);
      expect(cCnt, 4);
      expectError = true;
      expectation = 1;
      controller1.addError(1);
      expect(cCnt, 6);

      sub.cancel();
    });

    test('.react throws exceptions if no onError is provided', () async {
      final controller1 = StreamController<int>.broadcast(
          sync: true); // Use a broadcast stream to make debugging easier
      final source1 = controller1.stream;

      var cCnt = 0;

      final c = Computed(() {
        source1.react((p0) {});
        cCnt++;
      });

      var expectError = false;
      var expectation = 0;
      var lCnt = 0;

      final sub = c.listen((event) {
        lCnt++;
        expect(expectError, false);
      }, (e, st) {
        lCnt++;
        expect(expectError, true);
        expect(e, expectation);
      });

      expect(lCnt, 0);
      expect(cCnt, 2);
      // Await for Computed to call the listener
      await Future.value();
      expect(lCnt, 1);
      expectError = true;
      expectation = 1;

      controller1.addError(1);
      expect(cCnt, 2);
      expect(lCnt, 2);

      sub.cancel();
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
        source2.react((p0) {});

        return lCnt;
      });

      final c2 = Computed(() {
        source1.react((p0) {});
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

      sub.cancel();
    });
  });

  test(
      '(regression) gracefully handles sync exceptions while listening to data sources',
      () async {
    final s = StreamController();
    final stream = s.stream;
    stream.listen((event) {}).cancel(); // The stream is not usable anymore
    final c = $(() => stream.react((p0) {}));
    var cnt = 0;

    void valueListener(void event) => fail('must not produce a value');
    void errorListener(Object e) {
      expect(e, isA<StateError>());
      expect((e as StateError).message, 'Stream has already been listened to.');
      cnt++;
    }

    var sub = c.listen(valueListener, errorListener);
    expect(cnt, 0);
    await Future.value();
    expect(cnt, 1);

    sub.cancel();

    await Future.value();
    expect(cnt, 1); // Must not be called again

    sub = c.listen(valueListener, errorListener);

    expect(cnt, 1);
    await Future.value();
    expect(cnt, 2);

    sub.cancel();
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

    await Future.value();
    expect(flag, true);

    sub.cancel();
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

    await Future.value();
    expect(flag, true);

    sub.cancel();
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

    await Future.value();
    expect(flag, true);

    sub.cancel();
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

    expect(cnt1, 2);
    expect(cnt2, 2);
    expect(cnt3, 2);

    sub.cancel();
  });

  test('(regression) additionally listened computation are not recomputed',
      () async {
    final controller = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream;

    var cnt = 0;

    final c1 = Computed(() {
      cnt++;
      return source.use;
    });

    final c2 = Computed(() => c1.use);
    final c3 = Computed(() => c1.use);

    expect(cnt, 0);
    final sub1 = c2.listen((event) {}, (e) => fail(e.toString()));
    expect(cnt, 2);
    controller.add(0);
    expect(cnt, 4);
    final sub2 = c3.listen((event) {}, (e) => fail(e.toString()));
    expect(cnt, 4);
    controller.add(1);
    expect(cnt, 6);

    sub1.cancel();
    sub2.cancel();
  });

  test(
      '(regression) listeners attached and cancalled within the same microtask are not fired',
      () async {
    final c = $(() => 42);
    c.listen((_) => fail('must not fire'), (e) => fail(e.toString())).cancel();
    await Future.value();
    final sub1 = c.listen(null, null);
    c.listen((_) => fail('must not fire'), (e) => fail(e.toString())).cancel();
    await Future.value();
    sub1.cancel();
  });

  test('(regression) initial call to listeners are made with up-to-date values',
      () async {
    final s1 = StreamController(sync: true);
    final stream1 = s1.stream;
    final s2 = StreamController(sync: true);
    final stream2 = s2.stream;
    final c2 = $(() => stream2.use);
    final sub2 = c2.listen(null, null);
    s1.add(0);
    final c = $(() => stream1.use + stream2.useOr(0));
    var flag = false;
    final sub1 = c.listen((e) {
      expect(flag, false);
      expect(e, 1);
      flag = true;
    }, (e) => fail(e.toString()));
    s2.add(1);
    await Future.value();
    expect(flag, true);

    sub1.cancel();
    sub2.cancel();
  });

  test('(regression) listeners cannot .use', () async {
    final s = ValueStream<int>();
    s.add(0);

    final c1 = Computed(() => s.use);
    final c2 = Computed(() => c1.use);

    var flag = false;

    final sub = c2.listen((event) {
      try {
        s.use;
        fail("Must have thrown");
      } catch (e) {
        expect(e, isA<StateError>());
        expect((e as StateError).message,
            "`use`, `useWeak`, `react` and `prev` are only allowed inside computations.");
        flag = true;
      }
    }, (e) => fail(e.toString()));

    await Future.value();

    expect(flag, true);

    sub.cancel();
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

    sub.cancel();
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

    sub.cancel();
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

    sub.cancel();
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

    sub.cancel();
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

    sub.cancel();
  });

  test(
      '(regression) avoids dag state corruption if a computation re-runs with fewer dependencies but same result',
      () async {
    final controller1 = StreamController<int>.broadcast(
        sync: true); // Use a broadcast stream to make debugging easier
    final source1 = controller1.stream;

    final c2 = Computed(() => source1.use);

    var dependOnC2 = true;

    final c = Computed(() {
      if (dependOnC2) c2.use;
      return 0;
    });

    var subCnt = 0;

    final sub = c.listen((event) {
      subCnt++;
      expect(event, 0);
    }, (e) => fail(e.toString()));

    await Future.value();
    expect(subCnt, 0);
    controller1.add(0);
    await Future.value();
    expect(subCnt, 1);
    dependOnC2 = false;
    controller1.add(1);
    await Future.value();
    expect(subCnt, 1);
    controller1.add(2);
    await Future.value();
    expect(subCnt, 1);

    sub.cancel();
  });

  test(
      '(regression) avoids double-notifying new listeners if the computation changes value during the same microtask',
      () async {
    final s = StreamController(sync: true);
    final stream = s.stream;
    final c = $(() => stream.use);
    var flag = false;
    s.add(0);
    final sub2 = c.listen(null, null);
    await Future.value();
    // c now has a value
    final sub1 = c.listen((event) {
      expect(flag, false);
      expect(event, 1);
      flag = true;
    }, (e) => fail(e.toString()));
    // c changes value
    s.add(1);
    await Future.value();
    expect(flag, true);

    sub1.cancel();
    sub2.cancel();
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
            expect(source1.prevOr(42), expectation);
          } on NoValueException {
            expect(expectation, null);
            expect(source1.prevOr(42), 42);
          }
          return source1.use;
        });

        var subCnt = 0;

        final sub = c.listen((event) {
          subCnt++;
        }, (e) => fail(e.toString()));

        expect(subCnt, 0);
        controller1.add(0);
        expect(subCnt, 1);
        expectation = 0;
        controller1.add(1);
        expect(subCnt, 2);

        sub.cancel();
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

      expect(subCnt, 0);
      controller1.add(0);
      expect(subCnt, 0);
      expectation1 = 0;
      controller2.add(1);
      expect(subCnt, 1);
      expectation2 = 1;
      controller1.add(1);
      expect(subCnt, 2);
      expectation1 = 1;
      expectation2 = 1;
      controller1.add(2);
      expect(subCnt, 3);

      sub.cancel();
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

      sub.cancel();
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

      await Future.value();
      expect(subCnt, 0);
      controller1.add(0);
      expect(subCnt, 1);
      expectation = 0;
      controller1.add(1);
      expect(subCnt, 2);

      sub.cancel();
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

        await Future.value();
        expect(subCnt, 0);
        controller1.add(1);
        expect(subCnt, 1);
        prevExpectation = 1;
        controller1.add(2);
        expect(subCnt, 2);

        sub.cancel();
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

      sub.cancel();
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

      await Future.value();
      expect(subCnt, 1);
      controller1.add(0);
      expect(subCnt, 2);
      expectError = false;
      valueExpectation = 0;
      controller1.add(1);
      expect(subCnt, 3);

      sub.cancel();
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
      expectation1 = 3;
      controller2.add(4);
      expect(subCnt, 4);
      expectation1 = 3;
      expectation2 = 4;
      controller2.add(5);
      expect(subCnt, 5);

      sub.cancel();
    });

    test('can be used even if the last computation threw NVE', () async {
      final s = ValueStream.seeded(42, sync: true);
      int? res;
      final c2 = $(() {
        s.use;
        res = s.prev;
        throw NoValueException();
      });
      final sub = c2.listen(null);
      await Future.value(); // For [s] to notify Computed
      expect(res, null);
      s.add(43);
      expect(res, 42);
      sub.cancel();
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

      expect(flag, true);

      sub.cancel();
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

      await Future.value();
      expect(flag, true);

      sub.cancel();
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

      controller.add(1);

      expect(cnt1, 1);
      expect(cnt2, 0);

      createCycle = true;
      controller.add(2);

      expect(cnt1, 1);
      expect(cnt2, 1);

      sub.cancel();
    });

    test('unexpected .use does not re-compute upstream', () async {
      final s1 = ValueStream<int>(sync: true);
      s1.add(0);
      var c1Cnt = 0;

      final c1 = $(() {
        c1Cnt++;
        return s1.use;
      });

      final sub1 = c1.listen((event) {}, (e) => fail(e.toString()));

      expect(c1Cnt, 2);

      await Future.value();

      expect(c1Cnt, 4);

      final s2 = ValueStream<int>(sync: true);
      s2.add(0);
      var use1 = false;

      var c2Cnt = 0;

      final c2 = $(() {
        c2Cnt++;
        return s2.use + (use1 ? c1.use : 0);
      });

      final sub2 = c2.listen((event) {}, (e) => fail(e.toString()));

      expect(c2Cnt, 2);

      await Future.value();

      expect(c1Cnt, 4);
      expect(c2Cnt, 4);

      use1 = true;
      s2.add(1);

      await Future.value();

      expect(c1Cnt, 4);
      expect(c2Cnt, 6);

      sub1.cancel();
      sub2.cancel();
    });
  });

  test('can disable the idempotency check', () {
    var cCnt = 0;
    final c1 = Computed(() => cCnt++, assertIdempotent: false);
    c1.listen(null, null).cancel();
    expect(cCnt, 1);

    final c2 = Computed.withPrev((prev) => cCnt++,
        initialPrev: 0, assertIdempotent: false);
    c2.listen(null, null).cancel();
    expect(cCnt, 2);
  });

  group('async mode', () {
    test('disables the sync zone and idempotency checks', () async {
      var cCnt = 0;

      final c = Computed.async(() {
        cCnt++;
        return Future.microtask(() => 42);
      });

      var lCnt = 0;
      Future<int>? lastRes;

      final sub = c.listen((event) {
        lCnt++;
        lastRes = event;
      }, (e) => fail(e.toString()));

      expect(cCnt, 1);
      expect(lCnt, 0);
      await Future.value();
      expect(cCnt, 1);
      expect(lCnt, 1);
      expect(await lastRes, 42);

      sub.cancel();

      // Also test for `withPrev`
      final c2 =
          Computed.withPrev((prev) => cCnt++, initialPrev: 0, async: true);
      c2.listen(null, null).cancel();
      expect(cCnt, 2);

      // `assertIdempotent` is ignored
      final c3 = Computed.withPrev((prev) => cCnt++,
          initialPrev: 0, async: true, assertIdempotent: true);
      c3.listen(null, null).cancel();
      expect(cCnt, 3);
    });
  });

  group('dispose', () {
    test('is called when a computation changes value', () async {
      var cnt = 0;
      int? last;
      final s = ValueStream.seeded(() => 0, sync: true);
      final sub = Computed(() => s.use(), dispose: (e) {
        cnt++;
        last = e;
      }).listen(null, (_) {});

      for (var i = 0; i < 5; i++) {
        await Future.value();
      }

      expect(cnt, 0);
      s.add(() => 1);
      expect(cnt, 1);
      expect(last, 0);

      s.add(() => 2);
      expect(cnt, 2);
      expect(last, 1);

      // Also when a computation which has a value throws
      s.add(() => throw 42);
      expect(cnt, 3);
      expect(last, 2);

      // But not if the last run threw
      s.add(() => throw 43);
      expect(cnt, 3);

      // Not even if the next run returns a value
      s.add(() => 0);
      expect(cnt, 3);

      // Now it is back to normal
      s.add(() => 1);
      expect(cnt, 4);
      expect(last, 0);

      sub.cancel();
    });

    test('is called upon losing the last downstream computation', () async {
      var cCnt = 0;
      int? lastArg;
      final c1 = Computed<int>(() => 42, dispose: (value) {
        cCnt++;
        lastArg = value;
      });
      final c2 = $(() => c1.use);

      final sub =
          c2.listen((val) => expect(val, 42), (e) => fail(e.toString()));
      await Future.value();
      expect(cCnt, 0);
      sub.cancel();
      expect(cCnt, 1);
      expect(lastArg, 42);
    });
    test('is called upon losing the last listener', () async {
      var cCnt = 0;
      int? lastArg;
      final c = Computed<int>(() => 42, dispose: (value) {
        cCnt++;
        lastArg = value;
      });

      final sub = c.listen((val) => expect(val, 42), (e) => fail(e.toString()));
      await Future.value();
      expect(cCnt, 0);
      sub.cancel();
      expect(cCnt, 1);
      expect(lastArg, 42);
    });
    test('is not called for computations without a value', () async {
      final c = Computed<int>(() => throw NoValueException(),
          dispose: (value) => fail('must not call onDispose'));

      final sub = c.listen((val) => fail('must not notify the listener'),
          (e) => fail(e.toString()));
      await Future.value();
      sub.cancel();
      await Future.value();
    });

    test('is not called for computations which threw an exception', () async {
      final c = Computed<int>(() => throw 0,
          dispose: (value) => fail('must not call onDispose'));

      final sub =
          c.listen((val) => fail('must not notify the listener'), (e) => null);
      sub.cancel();
    });
  });

  group('onCancel', () {
    test('is called upon losing the last downstream computation', () async {
      var cCnt = 0;
      final c1 = Computed<int>(() => 42, onCancel: () => cCnt++);
      final c2 = $(() => c1.use);

      final sub = c2.listen((val) => expect(val, 42), null);
      await Future.value();
      expect(cCnt, 0);
      sub.cancel();
      expect(cCnt, 1);
    });
    test('is called even for computations without values', () async {
      var cCnt = 0;
      final c =
          Computed<int>(() => throw NoValueException(), onCancel: () => cCnt++);

      final sub = c.listen((val) => fail('Must not call the listener'), null);
      await Future.value();
      expect(cCnt, 0);
      sub.cancel();
      expect(cCnt, 1);
    });
    test('is called upon losing the last listener', () async {
      var cCnt = 0;
      final c = Computed<int>(() => 42, onCancel: () => cCnt++);

      final sub = c.listen((val) => expect(val, 42), null);
      await Future.value();
      expect(cCnt, 0);
      sub.cancel();
      expect(cCnt, 1);
    });
    test('is called after dispose', () async {
      var flag1 = false, flag2 = false;
      final c = Computed<int>(() => 0, dispose: (value) {
        expect(flag1, false);
        flag1 = true;
      }, onCancel: () {
        expect(flag1, true);
        expect(flag2, false);
        flag2 = true;
      });

      final sub = c.listen(null, null);
      sub.cancel();
      expect(flag2, true);
    });

    test('(regression) cancelling a weak user inside onCancel does not crash',
        () {
      late final ComputedSubscription<void> sub3;
      final c1 = Computed(() => 0, onCancel: () => sub3.cancel());
      final c2 = $(() => c1.use);

      final c3 = $(() => c2.useWeak);

      final sub2 = c2.listen(null);
      sub3 = c3.listen(null);

      sub2.cancel();
    });

    test(
        '(regression) re-cancelling a subscription inside onCancel does not crash',
        () {
      late final ComputedSubscription<void> sub2;
      final c1 = Computed(() => 0, onCancel: () => sub2.cancel());
      final c2 = $(() => c1.use);

      sub2 = c2.listen(null);

      sub2.cancel();
    });
  });
}
