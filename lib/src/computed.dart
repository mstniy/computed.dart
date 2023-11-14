import 'dart:async';

import '../computed.dart';

class NoValueException {}

class LastValue<T> {
  bool hasValue = false;
  T? lastValue;
}

class LastValueRouter<T> extends LastValue<T> {
  ComputedImpl<T> router;
  LastValueRouter(this.router);
}

class ComputedGlobalCtx {
  static ComputedImpl? _currentComputation;
  static ComputedImpl get currentComputation {
    if (_currentComputation == null) {
      throw StateError("`use` is only allowed inside Computed expressions.");
    }
    return _currentComputation!;
  }

  static final lvExpando = Expando<LastValueRouter>('computed_lv');
}

class ComputedStreamExtensionImpl<T> {
  final Stream<T> s;

  ComputedStreamExtensionImpl(this.s);
  T get use {
    final caller = ComputedGlobalCtx.currentComputation;
    // Maintain a global cache of stream last values for any new dependencies discovered to use
    var lv = ComputedGlobalCtx.lvExpando[s] as LastValueRouter<T>?;

    if (lv == null) {
      lv = LastValueRouter(ComputedImpl(() => s.use));
      ComputedGlobalCtx.lvExpando[s] = lv;
    }
    if (lv.router != caller) {
      // Subscribe to the router instead
      return lv.router.use;
    }
    // We are the router
    // Make sure we are subscribed
    caller._dataSources.putIfAbsent(
        s,
        () => s.listen((newValue) {
              if (lv!.hasValue && lv.lastValue == newValue) return;
              // Update the global last value cache
              lv.hasValue = true;
              lv.lastValue = newValue;
              caller._rerunGraph();
            })); // Handle onError (passthrough), onDone (close subscriptions to upstreams)
    if (!lv.hasValue) {
      throw NoValueException();
    }
    return lv.lastValue!;
  }
}

class ComputedSubscription<T> implements StreamSubscription<T> {
  final ComputedImpl<T> _node;
  void Function(T event)? _onData;
  Function? _onError;
  ComputedSubscription(this._node, this._onData, this._onError);
  @override
  Future<E> asFuture<E>([E? futureValue]) {
    throw UnimplementedError(); // Doesn't make much sense in this context
  }

  @override
  Future<void> cancel() async {
    _node._removeListener(this);
  }

  @override
  bool get isPaused => false; ////////what is this???

  @override
  void onData(void Function(T data)? handleData) {
    _onData = handleData;
  }

  @override
  void onDone(void Function()? handleDone) {
    // Computed streams are never done
  }

  @override
  void onError(Function? handleError) {
    _onError = handleError;
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    throw UnimplementedError(); //// what is this?????
  }

  @override
  void resume() {
    throw UnimplementedError(); //// what is this?????
  }
}

class ComputedStream<T> extends Stream<T> {
  ComputedImpl<T> _parent;

  ComputedStream(this._parent);

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final sub = ComputedSubscription<T>(_parent, onData, onError);
    if (_parent._dirty) {
      try {
        _parent._evalF();
        // Might set lastResult, won't notify the listener just yet (as that is against the Stream contract)
      } on NoValueException {}
    }
    _parent._listeners.add(sub);
    if (!_parent._dirty) {
      if (_parent._lastWasError! && onError != null) {
        final lastError = _parent._lastError!;
        scheduleMicrotask(() {
          onError(lastError);
        });
      } else if (!_parent._lastWasError! && onData != null) {
        final lastResult = _parent._lastResult!;
        scheduleMicrotask(() {
          onData(lastResult);
        });
      }
    }
    return sub;
  }
}

class ComputedImpl<T> implements Computed<T> {
  final _upstreamComputations = <ComputedImpl>{};
  final _downstreamComputations = <ComputedImpl>{};

  final _dataSources = <Stream, StreamSubscription>{};
  final _listeners = Set<ComputedSubscription<T>>();

  var _dirty = true;

  @override
  bool get evaluated => !_dirty;

  bool? _lastWasError;
  T? _lastResult;
  Object? _lastError;
  T? get lastResult {
    if (_lastWasError ?? false) throw _lastError!;
    return _lastResult;
  }

  final T Function() f;

  ComputedImpl(this.f);

  void _rerunGraph() {
    final numUnsatDep = <ComputedImpl, int>{};
    final resultDirty = <ComputedImpl>{this};
    final noUnsatDep = <ComputedImpl>{this};

    while (noUnsatDep.isNotEmpty) {
      final cur = noUnsatDep.first;
      noUnsatDep.remove(cur);
      if (!resultDirty.contains(cur)) continue;
      if (cur._downstreamComputations.isEmpty && cur._listeners.isEmpty) {
        continue;
      }
      final prevRes = cur
          .lastResult; // TODO: Consider the cases where f threw/throws this time
      cur._evalF();
      final resultChanged = cur.lastResult != prevRes;
      if (resultChanged) {
        cur._notifyListeners();
      }
      for (var down in cur._downstreamComputations) {
        if (resultChanged) resultDirty.add(down);
        final nud =
            (numUnsatDep[down] ?? down._upstreamComputations.length) - 1;
        if (nud == 0) {
          noUnsatDep.add(down);
        } else {
          numUnsatDep[down] = nud;
        }
      }
    }
  }

  void _evalF() {
    try {
      ComputedGlobalCtx._currentComputation = this;
      _lastResult = f();
      _lastError = null;
      _lastWasError = false;
      _dirty = false;
      // cancel subscriptions to unused streams & remove them from the context (bonus: allow the user to specify a duration before doing that)
    } on NoValueException catch (e) {
      // Not much we can do
      throw e;
    } catch (e) {
      _lastResult = null;
      _lastError = e;
      _lastWasError = true;
      _dirty = false;
    } finally {
      ComputedGlobalCtx._currentComputation = null;
    }
  }

  void _notifyListeners() {
    if (_lastError == null) {
      for (var listener in _listeners)
        if (listener._onData != null) listener._onData!(_lastResult!);
    } else {
      // Exception
      for (var listener in _listeners)
        if (listener._onError != null) listener._onError!(_lastError);
    }
  }

  void _removeDataSourcesAndUpstreams() {
    if (_upstreamComputations.isNotEmpty || _dataSources.isNotEmpty) {
      _dirty = true; // So that we re-run the next time we are subscribed to
    }
    for (var upComp in _upstreamComputations)
      upComp._removeDownstreamComputation(this);
    _upstreamComputations.clear();
    for (var strSub in _dataSources.entries) {
      strSub.value.cancel();
      if (ComputedGlobalCtx.lvExpando[strSub.key]?.router == this) {
        // If we are the router for this stream, remove ourselves from the expando
        ComputedGlobalCtx.lvExpando[strSub.key] = null;
      }
    }
    _dataSources.clear();
  }

  void _removeDownstreamComputation(ComputedImpl c) {
    assert(_downstreamComputations.remove(c));
    if (_downstreamComputations.isEmpty && _listeners.isEmpty) {
      _removeDataSourcesAndUpstreams();
    }
  }

  void _removeListener(ComputedSubscription<T> sub) {
    _listeners.remove(sub);
    if (_downstreamComputations.isEmpty && _listeners.isEmpty) {
      _removeDataSourcesAndUpstreams();
    }
  }

  T get use {
    final caller = ComputedGlobalCtx.currentComputation;
    // Make sure the caller is subscribed
    caller._upstreamComputations.add(this);
    this._downstreamComputations.add(caller);
    // Make sure we are computed
    if (_dirty) _evalF();
    assert(!_dirty);

    return lastResult!;
  }

  Stream<T> get asStream {
    return ComputedStream(this);
  }
}
