import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/src/computed.dart';
import 'package:test/test.dart';

void main() {
  test('unlistened computations are not computed', () {
    Computed(() => fail('must not be computed'));
  });
  test('computations can use streams', () {
    final controller = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream.asBroadcastStream();

    int? lastRes;

    final sub = Computed(() => source.use * 2).asStream.listen((event) {
      lastRes = event;
    }, onError: (e) => fail(e.toString()));

    try {
      controller.add(0);
      expect(lastRes, 0);
      controller.add(1);
      expect(lastRes, 2);
    } finally {
      sub.cancel();
    }
  });

  test('computations can use other computations', () {
    final controller = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream.asBroadcastStream();

    int? lastRes;

    final x2 = Computed(() => source.use * 2);

    final sub = Computed(() => x2.use + 1).asStream.listen((event) {
      lastRes = event;
    }, onError: (e) => fail(e.toString()));

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
    final controller = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream.asBroadcastStream();

    int? lastRes;

    final x2 = Computed<int>(() => source.use * source.use);

    var callCnt = 0;

    final sub = Computed(() {
      callCnt += 1;
      return x2.use;
    }).asStream.listen((event) {
      lastRes = event;
    }, onError: (e) => fail(e.toString()));

    expect(callCnt, 1);

    try {
      controller.add(0);
      expect(lastRes, 0);
      expect(callCnt, 3);
      controller.add(1);
      expect(lastRes, 1);
      expect(callCnt, 5);
      controller.add(1);
      expect(lastRes, 1);
      expect(callCnt, 5);
      controller.add(-1);
      expect(lastRes, 1);
      expect(callCnt, 5);
    } finally {
      sub.cancel();
    }
  });

  test('respects topological order on upstream updates', () {
    for (var streamFirst in [false, true]) {
      // Run the test twice to make sure the order of operations doesn't matter
      final controller = StreamController<int>(
          sync: true); // Use a broadcast stream to make debugging easier
      final source = controller.stream.asBroadcastStream();

      final outputs = <int>[];

      final x2 = Computed(() => source.use * 2);

      final x2_x = streamFirst
          ? Computed<int>(() => source.use + x2.use)
          : Computed<int>(() => x2.use + source.use);

      final sub = x2_x.asStream.listen((output) {
        outputs.add(output);
      }, onError: (e) => fail(e.toString()));

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

  test('respects topological order on upstream updates (bigger)', () {
    // Test with different combinations of orderings
    for (var a in [false, true]) {
      for (var b in [false, true]) {
        final controller1 = StreamController<int>.broadcast(
            sync: true); // Use a broadcast stream to make debugging easier
        final source1 = controller1.stream.asBroadcastStream();

        final controller2 = StreamController<int>.broadcast(
            sync: true); // Use a broadcast stream to make debugging easier
        final source2 = controller2.stream.asBroadcastStream();

        final c1 = Computed(() {
          final x = source1.use + source2.use;
          return x;
        });
        final c2 =
            Computed(() => a ? (c1.use + source1.use) : (source1.use + c1.use));
        final c3 =
            Computed(() => b ? (c1.use + source2.use) : (source2.use + c1.use));

        final outputs2 = <int>[];
        final outputs3 = <int>[];

        final sub2 = c2.asStream.listen((output) {
          outputs2.add(output);
        }, onError: (e) => fail(e.toString()));

        final sub3 = c3.asStream.listen((output) {
          outputs3.add(output);
        }, onError: (e) => fail(e.toString()));

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

  test('detaching all listeners disables the computation graph', () async {
    final controller = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream.asBroadcastStream();

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

    var sub = c2.asStream.listen((output) {
      checkCnt++;
      expect(output, 0);
    }, onError: (e) => fail(e.toString()));

    expect(callCnt1, 1);
    expect(callCnt2, 1);
    expect(checkCnt, 0);

    try {
      controller.add(0);
      expect(callCnt1, 3);
      expect(callCnt2, 3);
      await Future.value(); // Wait for the listener to fire
      expect(checkCnt, 1);
    } finally {
      sub.cancel();
    }

    controller.add(1); // Must not trigger a re-calculation
    expect(callCnt1, 3);
    expect(callCnt2, 3);
    expect(checkCnt, 1);

    sub = c2.asStream.listen((output) {
      expect(output, 4);
      checkCnt++;
    }, onError: (e) => fail(e.toString())); // This triggers a re-computation

    await Future.value();
    expect(callCnt1,
        4); // Attaching the listeners triggers a call to discover dependencies
    expect(callCnt2, 4);
    expect(checkCnt,
        1); // The listener is not run: no value was produced by the stream after the second listen

    controller.add(2); // Must trigger a re-calculation
    expect(callCnt1, 6);
    expect(callCnt2, 6);
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

    for (var i = 0; i < 2; i++) {
      final sub = c2.asStream.listen((output) {
        fail('must not reach here');
      }, onError: (e) {
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
    }
  });

  test('constant computations work', () async {
    var callCnt = 0;

    final c1 = Computed<int>(() {
      callCnt++;
      return 42;
    });

    var checkFlag = false;

    var sub = c1.asStream.listen((event) {
      expect(checkFlag, false);
      checkFlag = true;
      expect(event, 42);
    }, onError: (e) => fail(e.toString()));

    try {
      await Future.value(); // Wait for the update
      expect(checkFlag, true);
      expect(callCnt, 2);
    } finally {
      sub.cancel();
    }

    checkFlag = false;

    sub = c1.asStream.listen((event) {
      expect(checkFlag, false);
      checkFlag = true;
      expect(event, 42);
    }, onError: (e) => fail(e.toString()));

    try {
      await Future.value(); // Wait for the update
      expect(checkFlag, true);
      expect(callCnt, 2); // The constant does not get re-computed
    } finally {
      sub.cancel();
    }
  });

  test('detaching all listeners removes the expando', () async {
    final controller = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream.asBroadcastStream();

    final c = Computed(() {
      return source.use;
    });

    var sub =
        c.asStream.listen((output) {}, onError: (e) => fail(e.toString()));

    sub.cancel();

    expect(GlobalCtx.lvExpando[source], null);
  });

  test('cannot use `use` outside Computed expressions', () {
    final x = Stream.empty();
    try {
      x.use;
    } on StateError catch (e) {
      expect(e.message, '`use` is only allowed inside Computed expressions.');
    }
  });

  test('can use futures as data sources', () async {
    final completer = Completer<int>();
    final future = completer.future;

    final x2 = Computed(() => future.use * 2);
    final x3 = Computed(() => x2.use * future.use);

    var callCnt = 0;

    final sub = x3.asStream.listen((event) {
      callCnt++;
      expect(event, 8);
    }, onError: (e) => fail(e.toString()));

    try {
      completer.complete(2);
      await Future.value();
      expect(callCnt, 1);
    } finally {
      sub.cancel();
    }
  });

  test('can cancel futures', () async {
    final completer = Completer<int>();
    final future = completer.future;

    final x = Computed(() {
      future.use;
      fail('Must not run the computation');
    });

    final sub = x.asStream.listen((event) {
      fail('Must not call the listener');
    }, onError: (e) => fail(e.toString()));

    sub.cancel();

    completer.complete(0);

    await Future.value();

    // Nothing should be run
  });

  test('asserts on detected side effects', () {
    var ctr = 0;
    final c = Computed(() => ctr++);

    try {
      c.asStream.listen((event) {
        fail('Must not call listener');
      }, onError: (e) => fail(e.toString()));
      fail('Must assert');
    } on AssertionError catch (e) {
      expect(
          e.message,
          contains(
              "Computed expressions must be purely functional. Please use listeners for side effects."));
    } catch (e) {
      fail('Unexpected exception');
    }
  });

  test('fix and unmock works', () async {
    final controller = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream.asBroadcastStream();

    final c = Computed(() {
      return source.use;
    });

    var listenerCallCnt = 0;
    var expectation = 42;

    var sub = c.asStream.listen((output) {
      listenerCallCnt++;
      expect(output, expectation);
    }, onError: (e) => fail(e.toString()));

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

  test('fixException works', () async {
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

    var sub =
        c2.asStream.listen((output) {}, onError: (e) => fail(e.toString()));

    try {
      mustThrow = true;
      c1.fixException(42);
    } finally {
      sub.cancel();
    }

    expect(callCnt, 4);
  });

  test('computations can use and return null', () {
    final controller = StreamController<int?>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream.asBroadcastStream();

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

    final sub = c2.asStream.listen((event) {
      subCnt++;
      expect(event, expected);
    }, onError: (e) => fail(e.toString()));

    expect(c1cnt, 1);
    expect(c2cnt, 1);
    expect(subCnt, 0);

    try {
      expected = null;
      controller.add(null);
      expect(c1cnt, 3);
      expect(c2cnt, 3);
      expect(subCnt, 1);
      expected = 0;
      controller.add(0);
      expect(c1cnt, 5);
      expect(c2cnt, 5);
      expect(subCnt, 2);
      expected = null;
      controller.add(null);
      expect(c1cnt, 7);
      expect(c2cnt, 7);
      expect(subCnt, 3);
      controller.add(null);
      expect(c1cnt, 7);
      expect(c2cnt, 7);
      expect(subCnt, 3);
    } finally {
      sub.cancel();
    }
  });

  test('exceptions are not memoized', () {
    final controller = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream.asBroadcastStream();

    var c1cnt = 0;
    var c2cnt = 0;

    final c1 = Computed(() {
      c1cnt++;
      if (source.use % 2 == 0) throw 42;
      return source.use;
    });
    final c2 = Computed(() {
      c2cnt++;
      return c1.use;
    });

    var subCnt = 0;
    bool expectThrow = false;

    final sub = c2.asStream.listen((event) {
      subCnt++;
      expect(expectThrow, false);
    }, onError: (e) {
      subCnt++;
      expect(expectThrow, true);
    });

    expect(c1cnt, 1);
    expect(c2cnt, 1);
    expect(subCnt, 0);

    try {
      expectThrow = true;
      controller.add(0);
      expect(c1cnt, 2);
      expect(c2cnt, 2);
      expect(subCnt, 1);
      controller.add(2);
      expect(c1cnt, 3);
      expect(c2cnt, 3);
      expect(subCnt, 2);
      expectThrow = false;
      controller.add(1);
      expect(c1cnt, 5);
      expect(c2cnt, 5);
      expect(subCnt, 3);
      expectThrow = true;
      controller.add(0);
      expect(c1cnt, 6);
      expect(c2cnt, 6);
      expect(subCnt, 4);
    } finally {
      sub.cancel();
    }
  });

  test('cyclic dependency during initial computation throws CyclicUseException',
      () async {
    late Computed<int> b;
    final a = Computed(() => b.use);
    b = Computed(() => a.use);

    var flag = false;

    final sub = b.asStream.listen((event) {
      fail('What?');
    }, onError: (e) {
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

  test('abandoned dependencies are dropped', () {
    final controller = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source = controller.stream.asBroadcastStream();

    var dependOnSource = true;

    var cnt = 0;

    final c = Computed(() {
      cnt++;
      if (dependOnSource)
        return source.use;
      else
        return 1;
    });

    var subCnt = 0;
    var expectation = 0;

    final sub = c.asStream.listen((event) {
      subCnt++;
      expect(event, expectation);
    }, onError: (e) => fail(e.toString()));

    try {
      controller.add(0);
      expect(cnt, 3);
      expect(subCnt, 1);

      dependOnSource = false;
      expectation = 1;
      controller.add(2);
      expect(cnt, 5);
      expect(subCnt, 2);

      // From this point on c is regarded as a constant
      // Thus, adding items to the stream does not trigger a re-computation

      controller.add(3);
      expect(cnt, 5);
      expect(subCnt, 2);
    } finally {
      sub.cancel();
    }
  });

  test('can add new dependencies on subsequent calls', () async {
    final controller1 = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source1 = controller1.stream.asBroadcastStream();

    final controller2 = StreamController<int>(
        sync: true); // Use a broadcast stream to make debugging easier
    final source2 = controller2.stream.asBroadcastStream();

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

    final sub = c.asStream.listen((event) {
      subCnt++;
      expect(event, expectation);
    }, onError: (e) => fail(e.toString()));

    try {
      controller1.add(0);
      expect(cnt, 3);
      expect(subCnt, 1);

      dependOnSource2 = true;
      controller1.add(1);
      expect(cnt,
          4); // Attempted evaluation, failed with NoValueException on source2
      expect(subCnt, 1);

      expectation = 3;
      controller2.add(2);
      expect(cnt, 6);
      expect(subCnt, 2);
    } finally {
      sub.cancel();
    }
  });
}