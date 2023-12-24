import 'dart:async';

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

  void add(T t) {
    _lastWasError = false;
    _lastValue = t;
    if (_controller.hasListener) {
      // Otherwise the controller will buffer
      _controller.add(t);
    }
  }

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

class ResourceStream<T> extends ValueStream<T> {
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

  @override
  void add(T t) {
    _maybeDispose();
    super.add(t);
  }

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
