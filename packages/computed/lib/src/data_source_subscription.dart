// Very similar to StreamSubscription
// Except only the parts Computed needs
abstract class DataSourceSubscription<T> {
  Future<void> cancel();
}
