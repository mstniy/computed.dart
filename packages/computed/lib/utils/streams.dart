import 'dart:async';

sealed class _ValueOrException<T> {
  _ValueOrException._();

  factory _ValueOrException.value(T value) => Value(value);
  factory _ValueOrException.exc(Object exc, StackTrace? st) =>
      Exception(exc, st);
}

class Value<T> extends _ValueOrException<T> {
  final T _value;

  Value(this._value) : super._();
}

class Exception<T> extends _ValueOrException<T> {
  final Object exc;
  final StackTrace? st;

  Exception(this.exc, this.st) : super._();
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
class ValueStream<T> extends Stream<T> implements EventSink<T> {
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
    // If _lastNotifiedValue and _lastAddedValue have equal values,
    // skip notifying listeners.
    switch ((_lastNotifiedValue, _lastAddedValue)) {
      case (Value(_value: final v1), Value(_value: final v2)):
        if (v1 == v2) {
          return;
        }
      case _:
      // pass
    }
    if (_controller.hasListener) {
      // Otherwise the controller will buffer
      _lastNotifiedValue = _lastAddedValue;
      switch (_lastAddedValue!) {
        case Value<T>(_value: final value):
          _controller.add(value);
        case Exception<T>(exc: final exc, st: final st):
          _controller.addError(exc, st);
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
  @override
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
  @override
  void addError(Object o, [StackTrace? st]) {
    _lastAddedValue = _ValueOrException.exc(o, st);
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

  bool get hasListener => _controller.hasListener;

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
    if (_userOnListen != null) _userOnListen();
  }

  void _onCancel() {
    _lastNotifiedValue = null;
    _setController(); // The old one is no good anymore
    if (_userOnCancel != null) _userOnCancel();
  }

  @override
  void close() {
    // Nop
  }
}
