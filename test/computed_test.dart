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

  test('detaching all listeners disables the computation graph', () async {
    final controller = StreamController<int>(
        sync: true); // Use a sync controller to make debugging easier
    final source = controller.stream.asBroadcastStream();

    var callCnt1 = 0;
    var callCnt2 = 0;

    final c1 = Computed((ctx) {
      callCnt1 += 1;
      return ctx(source);
    });

    final c2 = Computed((ctx) {
      callCnt2 += 1;
      return ctx(c1) * 2;
    });

    var checkCnt = 0;

    var sub = c2.listen((output) {
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

    sub = c2.listen((output) {
      expect(output, (checkCnt == 1) ? 0 : 4);
      checkCnt++;
    }); // This triggers a re-computation

    await Future.value();
    expect(callCnt1,
        3); // Attaching the listeners triggers a call to discover dependencies
    expect(callCnt2, 3);
    expect(checkCnt, 2); // The listener is run with the old value
    // TODO: Weird behaviour, fix.

    controller.add(2); // Must trigger a re-calculation
    expect(callCnt1, 4);
    expect(callCnt2, 4);
    expect(checkCnt, 3);
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
