import 'dart:async';

import 'package:computed/computed.dart';
import 'package:test/test.dart';

void main() {
  test('unlistened computations are not computed', () {
    Computed((ctx) => fail('must not be computed'));
  });
  test('computations can use streams', () {
    final controller = StreamController<int>(
        sync: true); // Use a sync controller to make debugging easier
    final source = controller.stream.asBroadcastStream();

    int? lastRes;

    final sub = Computed((ctx) => ctx(source) * 2).listen((event) {
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

    final x2 = Computed((ctx) => ctx(source) * 2);

    final sub = Computed((ctx) => ctx(x2) + 1).listen((event) {
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

    final x2 = Computed<int>((ctx) => ctx(source) * ctx(source));

    var callCnt = 0;

    final sub = Computed((ctx) {
      callCnt += 1;
      return ctx(x2);
    }).listen((event) {
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

      final x2 = Computed((ctx) => ctx(source) * 2);

      final x2_x = streamFirst
          ? Computed<int>((ctx) => ctx(source) + ctx(x2))
          : Computed<int>((ctx) => ctx(x2) + ctx(source));

      final sub = x2_x.listen((output) {
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

  test('attaching a listener runs computations if their results are dirty',
      () async {
    final controller = StreamController<int>(
        sync: true); // Use a sync controller to make debugging easier
    final source = controller.stream.asBroadcastStream();

    var callCnt = 0;

    final c = Computed((ctx) {
      callCnt += 1;
      return ctx(source);
    });

    var sub = c.listen((output) {
      expect(output, 0);
    });

    expect(callCnt, 1);

    try {
      controller.add(0);
      expect(callCnt, 2);
    } finally {
      sub.cancel();
    }

    controller.add(1); // Must not trigger a re-calculation
    expect(callCnt, 2);

    var checkRan = false;

    sub = c.listen((output) {
      expect(output, 1);
      checkRan = true;
    }); // This triggers a re-computation
    await Future.value(); // Wait for the microtask update
    expect(callCnt, 3);
    expect(checkRan, true);
  });

  test(
      'attaching a listener does not run the computation if the result are not dirty',
      () async {
    final controller = StreamController<int>(
        sync: true); // Use a sync controller to make debugging easier
    final source = controller.stream.asBroadcastStream();

    var callCnt = 0;

    final c = Computed((ctx) {
      callCnt += 1;
      return ctx(source);
    });

    var sub = c.listen((output) {
      expect(output, 0);
    });

    expect(callCnt, 1);

    try {
      controller.add(0);
      expect(callCnt, 2);
    } finally {
      sub.cancel();
    }

    var checkRan = false;

    sub = c.listen((output) {
      expect(output, 0);
      checkRan = true;
    }); // No need to re-compute the result: None of the parameters of the computation has changed
    await Future.value(); // Wait for the microtask update
    expect(callCnt, 2);
    expect(checkRan, true);
  });

  test('exceptions raised by computations are propagated', () async {
    var callCnt = 0;

    final c1 = Computed<int>((ctx) {
      callCnt++;
      throw 42;
    });

    final c2 = Computed((ctx) => ctx(c1));

    var checkFlag = false;

    for (var i = 0; i < 2; i++) {
      final sub = c2.listen((output) {
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

    final c1 = Computed<int>((ctx) {
      callCnt++;
      return 42;
    });

    var checkFlag = false;

    final sub = c1.listen((event) {
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
}
