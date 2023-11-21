import 'computed.dart';
import '../computed.dart';
import 'data_source_subscription.dart';

class FutureComputedExtensionImpl<T> {
  final Future<T> f;

  FutureComputedExtensionImpl(this.f);
  T get use {
    final caller = GlobalCtx.currentComputation;
    return caller.useDataSource(
        f,
        () => f.use,
        (onData, onError) =>
            _FutureDataSourceSubscription<T>(f, onData, onError),
        false,
        null);
  }
}

class _FutureDataSourceSubscription<T> implements DataSourceSubscription<T> {
  final void Function(T data) onValue;
  final Function onError;

  _FutureDataSourceSubscription(Future<T> f, this.onValue, this.onError) {
    f.then(this.onValue, onError: this.onError);
  }

  @override
  Future<void> cancel() {
    // We don't need to do anything here.
    // There is no way to cancel a Future and the router will already have lost all its downstream computations.
    return Future.value();
  }
}
