import 'dart:async';

import '../computed.dart';
import 'computed.dart';

class ComputedStreamExtensionImpl<T> {
  final ComputedImpl<T> _parent;
  StreamController<T>? _controller;
  ComputedSubscription<T>? _computedSubscription;
  bool? _isBroadcast;

  ComputedStreamExtensionImpl(Computed<T> parent)
      : _parent = parent as ComputedImpl<T>;

  Stream<T> get asStream {
    _isBroadcast = false;
    _controller ??=
        StreamController<T>(onListen: _onListen, onCancel: _onCancel);
    return _controller!.stream;
    // No onPause and onResume, as Computed doesn't support these.
  }

  Stream<T> get asBroadcastStream {
    _isBroadcast = true;
    _controller ??=
        StreamController<T>.broadcast(onListen: _onListen, onCancel: _onCancel);
    return _controller!.stream;
    // No onPause and onResume, as Computed doesn't support these.
  }

  void _onListen() {
    _computedSubscription ??= _parent.listen((event) => _controller!.add(event),
        onError: (error) => _controller!.addError(error),
        memoize: _isBroadcast!);
  }

  void _onCancel() {
    _computedSubscription?.cancel();
    _computedSubscription = null;
  }
}
