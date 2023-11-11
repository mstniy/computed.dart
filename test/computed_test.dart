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
}
