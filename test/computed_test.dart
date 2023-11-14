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
        sync: true); // Use a sync controller to make debugging easier
    final source = controller.stream.asBroadcastStream();

    int? lastRes;

    final sub = Computed(() => source.use * 2).asStream.listen((event) {
      lastRes = event;
    });

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
        sync: true); // Use a sync controller to make debugging easier
    final source = controller.stream.asBroadcastStream();

    int? lastRes;

    final x2 = Computed(() => source.use * 2);

    final sub = Computed(() => x2.use + 1).asStream.listen((event) {
      lastRes = event;
    });

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
        sync: true); // Use a sync controller to make debugging easier
    final source = controller.stream.asBroadcastStream();

    int? lastRes;

    final x2 = Computed<int>(() => source.use * source.use);

    var callCnt = 0;

    final sub = Computed(() {
      callCnt += 1;
      return x2.use;
    }).asStream.listen((event) {
      lastRes = event;
    });

    try {
      controller.add(0);
      expect(lastRes, 0);
      expect(callCnt, 2);
      controller.add(1);
      expect(lastRes, 1);
      expect(callCnt, 3);
      controller.add(1);
      expect(lastRes, 1);
      expect(callCnt, 3);
      controller.add(-1);
      expect(lastRes, 1);
      expect(callCnt, 3);
    } finally {
      sub.cancel();
    }
  });

  test('respects topological order on upstream updates', () {
    for (var streamFirst in [false, true]) {
      // Run the test twice to make sure the order of operations doesn't matter
      final controller = StreamController<int>(
          sync: true); // Use a sync controller to make debugging easier
      final source = controller.stream.asBroadcastStream();

      final outputs = <int>[];

      final x2 = Computed(() => source.use * 2);

      final x2_x = streamFirst
          ? Computed<int>(() => source.use + x2.use)
          : Computed<int>(() => x2.use + source.use);

      final sub = x2_x.asStream.listen((output) {
        outputs.add(output);
      });

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

  test('detaching all listeners disables the computation graph', () async {
    final controller = StreamController<int>(
        sync: true); // Use a sync controller to make debugging easier
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
    });

    expect(callCnt1, 1);
    expect(callCnt2, 1);
    expect(checkCnt, 0);

    try {
      controller.add(0);
      expect(callCnt1, 2);
      expect(callCnt2, 2);
      await Future.value(); // Wait for the listener to fire
      expect(checkCnt, 1);
    } finally {
      sub.cancel();
    }

    controller.add(1); // Must not trigger a re-calculation
    expect(callCnt1, 2);
    expect(callCnt2, 2);
    expect(checkCnt, 1);

    sub = c2.asStream.listen((output) {
      expect(output, 4);
      checkCnt++;
    }); // This triggers a re-computation

    await Future.value();
    expect(callCnt1,
        3); // Attaching the listeners triggers a call to discover dependencies
    expect(callCnt2, 3);
    expect(checkCnt,
        1); // The listener is not run: no value was produced by the stream after the second listen

    controller.add(2); // Must trigger a re-calculation
    expect(callCnt1, 4);
    expect(callCnt2, 4);
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

    final sub = c1.asStream.listen((event) {
      checkFlag = true;
      expect(event, 42);
    });

    try {
      await Future.value(); // Wait for the update
      expect(checkFlag, true);
      expect(callCnt, 1);
    } finally {
      sub.cancel();
    }
  });

  test('detaching all listeners removes the expando', () async {
    final controller = StreamController<int>(
        sync: true); // Use a sync controller to make debugging easier
    final source = controller.stream.asBroadcastStream();

    final c = Computed(() {
      return source.use;
    });

    var sub = c.asStream.listen((output) {});

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
    });

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
    });

    sub.cancel();

    completer.complete(0);

    await Future.value();

    // Nothing should be run
  });
}
