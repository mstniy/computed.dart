import 'dart:async';

import '../computed.dart';

import 'computed.dart';
import 'data_source_subscription.dart';

class StreamComputedExtensionImpl<T> {
  final Stream<T> s;

  StreamComputedExtensionImpl(this.s);

  T get use {
    final caller = GlobalCtx.currentComputation;
    return caller.dataSourceUse(
        s,
        (router) => _StreamDataSourceSubscription(s.listen(
            (data) => router.onDataSourceData(data),
            onError: (e, st) => router.onDataSourceError(e, st))),
        null);
  }

  T useOr(T value) {
    try {
      return use;
    } on NoValueException {
      return value;
    }
  }

  void react(void Function(T) onData, [Function? onError]) {
    final caller = GlobalCtx.currentComputation;
    caller.dataSourceReact<T>(
        s,
        (router) => _StreamDataSourceSubscription(s.listen(
            (data) => router.onDataSourceData(data),
            onError: (e, st) => router.onDataSourceError(e, st))),
        null,
        onData,
        onError);
  }

  T get prev {
    final caller = GlobalCtx.currentComputation;
    return caller.dataSourcePrev(s);
  }

  T prevOr(T or) {
    final caller = GlobalCtx.currentComputation;
    return caller.dataSourcePrevOr(s, or);
  }
}

class _StreamDataSourceSubscription<T> implements DataSourceSubscription<T> {
  final StreamSubscription<T> ss;
  _StreamDataSourceSubscription(this.ss);

  @override
  Future<void> cancel() {
    return ss.cancel();
  }
}
