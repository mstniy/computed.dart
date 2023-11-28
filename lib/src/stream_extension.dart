import 'dart:async';

import 'computed.dart';
import '../computed.dart';
import 'data_source_subscription.dart';

class StreamComputedExtensionImpl<T> {
  final Stream<T> s;

  StreamComputedExtensionImpl(this.s);
  T _use(bool memoized) {
    final caller = GlobalCtx.currentComputation;
    return caller.useDataSource(
        s,
        () => s.use,
        (router) => _StreamDataSourceSubscription(s.listen(
            (data) => router.onDataSourceData(data),
            onError: (e) => router.onDataSourceError(e))),
        false,
        null,
        memoized);
  }

  T get use {
    return _use(true);
  }

  T get useAll {
    return _use(false);
  }

  T get prev {
    final caller = GlobalCtx.currentComputation;
    return caller.dataSourcePrev(s);
  }

  bool get updated {
    return dataSourceUpdated(s);
  }

  void mockEmit(T value) {
    GlobalCtx.routerFor(s)?.onDataSourceData(value);
  }

  void mockEmitError(Object e) {
    GlobalCtx.routerFor(s)?.onDataSourceError(e);
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
