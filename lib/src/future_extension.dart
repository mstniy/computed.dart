import 'package:computed/computed.dart';

import 'computed.dart';
import 'data_source_subscription.dart';

class FutureComputedExtensionImpl<T> {
  final Future<T> f;

  FutureComputedExtensionImpl(this.f);
  T get use {
    final caller = GlobalCtx.currentComputation;
    return caller.dataSourceUse(
        f, (router) => _FutureDataSourceSubscription<T>(f, router), null);
  }

  T useOr(T value) {
    try {
      return use;
    } on NoValueException {
      return value;
    }
  }
}

class _FutureDataSourceSubscription<T> implements DataSourceSubscription<T> {
  _FutureDataSourceSubscription(Future<T> f, ComputedImpl<T> router) {
    f.then((value) => router.onDataSourceData(value),
        onError: (e) => router.onDataSourceError(e));
  }

  @override
  Future<void> cancel() {
    // We don't need to do anything here.
    // There is no way to cancel a Future and the router will already have lost all its downstream computations.
    return Future.value();
  }
}
