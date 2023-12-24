import 'dart:async';

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
  T? _lastValue;
  Object? _lastError;
  bool? _lastWasError;
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

  /// Adds the given value to this stream, unless if it compares `==` to the last added value.
  /// If there are no listeners, buffers the last value.
  void add(T t) {
    if (_lastWasError == false && _lastValue == t) return;
    _lastWasError = false;
    _lastValue = t;
    if (_controller.hasListener) {
      // Otherwise the controller will buffer
      _controller.add(t);
    }
  }

  /// Adds the given error to this stream.
  /// If there are no listeners, buffers the last error.
  void addError(Object o) {
    _lastWasError = true;
    _lastError = o;
    if (_controller.hasListener) {
      // Otherwise the controller will buffer
      _controller.addError(o);
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
        StreamController(sync: _sync, onListen: _onListen, onCancel: _onCancel);
  }

  void _onListen() {
    if (_lastWasError == false) {
      _controller.add(_lastValue as T);
    } else if (_lastWasError == true) {
      _controller.addError(_lastError!);
    }
    if (_userOnListen != null) _userOnListen!();
  }

  void _onCancel() {
    _setController(); // The old one is no good anymore
    if (_userOnCancel != null) _userOnCancel!();
  }
}

/// A [Stream] of resources.
///
/// This class is similar in semantics to [ValueStream], except that it creates new resources
/// using the provided function when a new listener is attached, unless if there is an existing
/// non-disposed resource, and disposes of the existing resource, if there is any, upon listener
/// cancellation and the addition of a new resource/error.
class ResourceStream<T> extends ValueStream<T> {
  /// A [ResourceStream] with functions to create and dispose of resources.
  ResourceStream(this._create, this._dispose,
      {void Function()? onListen,
      FutureOr<void> Function()? onCancel,
      bool sync = false})
      : super(onListen: onListen, onCancel: onCancel, sync: sync);

  final T Function() _create;
  final void Function(T) _dispose;

  @override
  void _onListen() {
    if (_lastWasError != false) {
      try {
        _lastValue = _create();
        _lastWasError = false;
      } catch (e) {
        _lastWasError = true;
        _lastError = e;
      }
    }
    super._onListen();
  }

  @override
  void _onCancel() {
    _maybeDispose();
    super._onCancel();
  }

  /// Adds the given resource to this stream.
  /// If there is an existing resource, disposes of it.
  /// If there are no listeners, buffers the last resource.
  @override
  void add(T t) {
    _maybeDispose();
    super.add(t);
  }

  /// Adds the given error to this stream.
  /// If there is an existing resource, disposes of it.
  /// If there are no listeners, buffers the last error.
  @override
  void addError(Object o) {
    _maybeDispose();
    super.addError(o);
  }

  void _maybeDispose() {
    if (_lastWasError == false) _dispose(_lastValue as T);
    _lastWasError = null;
  }
}
