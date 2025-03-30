import 'dart:async';

import '../computed.dart';

class ComputedStreamExtensionImpl<T> {
  final Computed<T> _parent;
  StreamController<T>? _controller;
  ComputedSubscription<T>? _computedSubscription;

  ComputedStreamExtensionImpl(this._parent);

  Stream<T> get asStream {
    _controller ??=
        StreamController<T>(onListen: _onListen, onCancel: _onCancel);
    return _controller!.stream;
    // No onPause and onResume, as Computed doesn't support these.
  }

  Stream<T> get asBroadcastStream {
    _controller ??=
        StreamController<T>.broadcast(onListen: _onListen, onCancel: _onCancel);
    return _controller!.stream;
    // No onPause and onResume, as Computed doesn't support these.
  }

  void _onListen() async {
    // StreamController can call onListen synchronously,
    // so call .listen in a separate microtask.
    await Future.value();
    _computedSubscription ??= _parent.listen((event) => _controller!.add(event),
        (error) => _controller!.addError(error));
  }

  void _onCancel() {
    _computedSubscription?.cancel();
    _computedSubscription = null;
  }
}
