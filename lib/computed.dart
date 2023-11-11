import 'dart:async';

import 'src/computed.dart';

abstract class ComputedStreamResolver {
  T call<T>(Stream<T> s);
}

abstract class Computed<T> extends Stream<T> {
  bool get hasLastResult;
  T? get lastResult;
  factory Computed(T Function(ComputedStreamResolver ctx) f) => ComputedImpl(f);
}
