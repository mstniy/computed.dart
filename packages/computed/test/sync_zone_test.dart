import 'dart:async';

import 'package:computed/computed.dart';
import 'package:test/test.dart';

Future<void> expectThrowsAsyncError(void Function() f) async {
  final c = $(f);
  var flag = false;
  final sub = c.listen((event) => fail('Must not produce a value'), (e) {
    expect(flag, false);
    flag = true;
    expect(e, isA<ComputedAsyncError>());
  });
  await Future.value();
  expect(flag, true);
  sub.cancel();
}

void main() {
  test(
      'disallows createPeriodicTimer',
      () => expectThrowsAsyncError(() => Zone.current
          .createPeriodicTimer(const Duration(seconds: 1), (timer) {})));

  test(
      'disallows createTimer',
      () => expectThrowsAsyncError(
          () => Zone.current.createTimer(const Duration(seconds: 1), () {})));

  test('intercepts errorCallback', () async {
    final controller = StreamController();
    await expectThrowsAsyncError(() => controller.addError(42));
  });

  test('disallows fork',
      () => expectThrowsAsyncError(() => Zone.current.fork()));

  test(
      'disallows registerBinaryCallback',
      () => expectThrowsAsyncError(
          () => Zone.current.registerBinaryCallback((int a, int b) => a + b)));

  test(
      'disallows registerCallback',
      () => expectThrowsAsyncError(
          () => Zone.current.registerCallback(() => 42)));

  test(
      'disallows registerUnaryCallback',
      () => expectThrowsAsyncError(
          () => Zone.current.registerUnaryCallback((_) => 42)));
}
