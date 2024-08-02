import '../computed.dart';

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
        // Note that although we capture the stack trace here,
        // there is no way for the user to actually access it,
        // as Future does not support .react
        // and .use does not preserve the origin stack trace
        onError: (e, st) => router.onDataSourceError(e, st));
  }

  @override
  Future<void> cancel() {
    // We don't need to do anything here.
    // There is no way to cancel a Future and the router will already have lost all its downstream computations.
    return Future.value();
  }
}
