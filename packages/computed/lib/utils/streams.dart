import 'dart:async';

class _ValueOrException<T> {
  final bool _isValue;
  Object? _exc;
  T? _value;

  _ValueOrException.value(this._value) : _isValue = true;
  _ValueOrException.exc(this._exc) : _isValue = false;
}

/// A [StreamController]-like class.
///
/// This class:
/// - Is a [Stream] by itself.
/// - Is not a broadcast stream (cannot have multiple listeners).
/// - Does not buffer added values/errors if there are no listeners, except for the last one.
/// - Can be re-listened after the existing listener is cancelled.
/// - Produces the last value or error to new listeners, if there is any.
///
/// Note that most of these properties are similar to rxdart's BehaviorSubject.
class ValueStream<T> extends Stream<T> {
  late StreamController<T> _controller;
  _ValueOrException<T>? _lastNotifiedValue;
  _ValueOrException<T>? _lastAddedValue;
  bool _controllerAddScheduled = false;
  final bool _sync;
  final void Function()? _userOnListen;
  final void Function()? _userOnCancel;

  ValueStream(
      {void Function()? onListen,
      FutureOr<void> Function()? onCancel,
      bool sync = false})
      : _userOnListen = onListen,
        _userOnCancel = onCancel,
        _sync = sync {
    _setController();
  }

  /// Constructs a [ValueStream] with an initial value
  factory ValueStream.seeded(T initialValue,
      {void Function()? onListen,
      FutureOr<void> Function()? onCancel,
      bool sync = false}) {
    final res =
        ValueStream<T>(onListen: onListen, onCancel: onCancel, sync: sync);
    res.add(initialValue);
    return res;
  }

  void _controllerAddMicrotask() {
    _controllerAddScheduled = false;
    if (_lastNotifiedValue?._isValue == true &&
        _lastAddedValue!._isValue &&
        _lastNotifiedValue!._value == _lastAddedValue!._value) return;
    if (_controller.hasListener) {
      // Otherwise the controller will buffer
      _lastNotifiedValue = _lastAddedValue;
      if (_lastAddedValue!._isValue) {
        _controller.add(_lastAddedValue!._value as T);
      } else {
        _controller.addError(_lastAddedValue!._exc!);
      }
    }
  }

  /// Adds [t] to this stream.
  ///
  /// If this ValueStream is sync, notifies listeners before returning,
  /// unless if [t] compares `==` to the value last used to notify the listeners.
  /// If this ValueStream is not sync, notifies listeners in the next microtask.
  /// Further calls to [add] or [addError] within a single microtask will
  /// override previous calls.
  /// In the next microtask, the listeners are notified with the last-added
  /// value, unless if it compares `==` to the value last used to notify them.
  ///
  /// If there are no listeners, buffers [t] and drops any previusly
  /// buffered values/errors.
  void add(T t) {
    _lastAddedValue = _ValueOrException.value(t);
    if (!_sync && _controller.hasListener) {
      if (_controllerAddScheduled) return;
      _controllerAddScheduled = true;
      scheduleMicrotask(_controllerAddMicrotask);
    } else {
      _controllerAddMicrotask();
    }
  }

  /// As with [add], but for adding errors.
  void addError(Object o) {
    _lastAddedValue = _ValueOrException.exc(o);
    if (!_sync && _controller.hasListener) {
      if (_controllerAddScheduled) return;
      _controllerAddScheduled = true;
      scheduleMicrotask(_controllerAddMicrotask);
    } else {
      _controllerAddMicrotask();
    }
  }

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  void _setController() {
    _controller =
        StreamController(sync: true, onListen: _onListen, onCancel: _onCancel);
  }

  void _onListen() {
    if (_lastAddedValue != null) {
      if (_controllerAddScheduled) return;
      _controllerAddScheduled = true;
      scheduleMicrotask(_controllerAddMicrotask);
    }
    if (_userOnListen != null) _userOnListen!();
  }

  void _onCancel() {
    _lastNotifiedValue = null;
    _setController(); // The old one is no good anymore
    if (_userOnCancel != null) _userOnCancel!();
  }
}
