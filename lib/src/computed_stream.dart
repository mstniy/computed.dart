import 'dart:async';

import '../computed.dart';
import 'computed.dart';

class ComputedStreamExtensionImpl<T> {
  final ComputedImpl<T> _parent;
  StreamController<T>? _controller;
  ComputedSubscription<T>? _computedSubscription;

  ComputedStreamExtensionImpl(Computed<T> parent)
      : _parent = parent as ComputedImpl<T>;

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

  void _onListen() {
    _computedSubscription ??= _parent.listen((event) => _controller!.add(event),
        (error) => _controller!.addError(error));
  }

  void _onCancel() {
    _computedSubscription?.cancel();
    _computedSubscription = null;
  }
}
