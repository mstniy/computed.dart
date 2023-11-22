import 'dart:async';

import '../computed.dart';
import 'computed.dart';

class _ComputedStreamSubscription<T> implements StreamSubscription<T> {
  final ComputedSubscription<T> _sub;
  _ComputedStreamSubscription(this._sub);

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    throw UnsupportedError(
        'asFuture not supported by Stream subscriptions to Computed'); // Doesn't make much sense in this context
  }

  @override
  Future<void> cancel() async {
    _sub.cancel();
  }

  @override
  bool get isPaused => false;

  @override
  void onData(void Function(T data)? handleData) {
    _sub.onData(handleData);
  }

  @override
  void onDone(void Function()? handleDone) {
    throw UnimplementedError();
  }

  @override
  void onError(Function? handleError) {
    _sub.onError(handleError);
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    throw UnimplementedError();
  }

  @override
  void resume() {
    throw UnimplementedError();
  }
}

class ComputedStream<T> extends Stream<T> {
  final ComputedImpl<T> _parent;

  ComputedStream(Computed<T> parent) : _parent = parent as ComputedImpl<T>;

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _ComputedStreamSubscription(_parent.listen(onData, onError));
  }
}
