import 'dart:async';
import 'dart:collection';

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

class SubscriptionLastValue<T> extends LastValue<T> {
  StreamSubscription<T>? subscription;
}

class ComputedGlobalCtx {
  static final lvExpando = Expando<LastValueRouter>('computed_lv');
}

class ComputedStreamResolverImpl implements ComputedStreamResolver {
  final ComputedImpl _parent;
  ComputedStreamResolverImpl(this._parent);
  T call<T>(Stream<T> s) {
    if (s is ComputedImpl<T>) {
      // Make sure we are subscribed
      _parent._upstreamComputations.putIfAbsent(
          s,
          () => s._listen(_parent, _parent.depth, (event) {
                try {
                  _parent._maybeEvalF(true, null, null);
                } on NoValueException {}
              })); // Handle onError (passthrough), onDone (close subscriptions to upstreams)
      // Update our depth
      if (s.depth + 1 > _parent.depth) {
        final oldDepth = _parent.depth;
        final newDepth = s.depth + 1;
        // Also modify the _listeners-s of upstream computations
        _parent._upstreamComputations.forEach((upstreamNode, subscription) {
          assert(upstreamNode._listeners[oldDepth]!.remove(subscription));
          upstreamNode._addListenerInternal(newDepth, subscription);
        });
        _parent.depth = newDepth;
      }

      if (!s._hasLastResult) s._evalF(); // Only do this once per computation
      return s._lastResult!; // What if f throws? _lastResult won't be set then
    } else {
      // Maintain a global cache of stream last values for any new dependencies discovered to use
      var lv = ComputedGlobalCtx.lvExpando[s] as LastValueRouter<T>?;

      if (lv == null) {
        lv = LastValueRouter(ComputedImpl((ctx) => ctx(s)));
        ComputedGlobalCtx.lvExpando[s] = lv;
      }
      if (lv.router != this._parent) {
        // Subscribe to the router instead
        return call(lv.router);
      }
      // We are the router
      // Make sure we are subscribed
      _parent._dataSources.putIfAbsent(s, () {
        final slv = SubscriptionLastValue();
        slv.subscription = s.listen((newValue) {
          final oldHasValue = slv.hasValue;
          final oldLastValue = slv.lastValue;
          slv.hasValue = true;
          slv.lastValue = newValue;
          if (identityHashCode(lv!.lastValue) != identityHashCode(newValue)) {
            // Update the global last value cache
            lv.hasValue = true;
            lv.lastValue = newValue;
          }
          _parent._maybeEvalF(!oldHasValue, oldLastValue, newValue);
        });
        return slv;
      }); // Handle onError (passthrough), onDone (close subscriptions to upstreams)
      if (!lv.hasValue) {
        throw NoValueException();
      }
      return lv.lastValue!;
    }
  }
}

class ComputedSubscription<T> implements StreamSubscription<T> {
  final ComputedImpl? _creator;
  final ComputedImpl<T> _parent;
  void Function(T event)? _onData;
  Function? _onError;
  ComputedSubscription(
      this._parent, this._creator, this._onData, this._onError);
  @override
  Future<E> asFuture<E>([E? futureValue]) {
    throw UnimplementedError(); // Doesn't make much sense in this context
  }

  @override
  Future<void> cancel() async {
    _parent._removeListener(this);
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

class ComputedImpl<T> extends Stream<T> implements Computed<T> {
  final _upstreamComputations = <ComputedImpl, ComputedSubscription>{};

  var _depth = 0;
  var depthDirty = false;
  var dirtyDepth = 0;

  int get depth {
    if (depthDirty) {
      if (dirtyDepth > _depth) {
        depth = dirtyDepth;
      }
      depthDirty = false;
    }
    return _depth;
  }

  void set depth(int newDepth) {
    if (_depth == newDepth) return;
    for (var listeners in _listeners.values) {
      for (var listener in listeners) {
        if (listener._creator != null) {
          listener._creator!.depthDirty = true;
          listener._creator!.dirtyDepth = newDepth + 1;
        }
      }
    }
    _depth = newDepth;
  }

  final _dataSources = <Stream, SubscriptionLastValue>{};
  final _listeners = SplayTreeMap<int, Set<ComputedSubscription<T>>>();
  var _numListeners = 0; // Note that this is NOT equal to _listeners.length
  var _suppressedEvalDueToNoListener = true;
  var _hasLastResult = false;
  bool get hasLastResult => _hasLastResult;

  T? _lastResult;
  T? get lastResult => _lastResult;
  final T Function(ComputedStreamResolver ctx) f;

  ComputedImpl(this.f);

  void _evalF() {
    _suppressedEvalDueToNoListener = false;
    late T fRes;
    var fFinished = false;
    try {
      fRes = f(ComputedStreamResolverImpl(this));
      // cancel subscriptions to unused streams & remove them from the context (bonus: allow the user to specify a duration before doing that)
      fFinished = true;
    } on NoValueException catch (e) {
      // Not much we can do
      throw e;
    } catch (e) {
      _notifyListeners(null, e);
    }
    if (fFinished) {
      _maybeNotifyListeners(fRes, null);
    }
  }

  void _maybeNotifyListeners(T? t, dynamic error) {
    if (error == null) {
      // Not an exception
      if (_hasLastResult == true && t == lastResult) return;
      _lastResult = t;
      _hasLastResult = true;
    }
    _notifyListeners(t, error);
  }

  void _notifyListeners(T? t, dynamic error) {
    // Eagerly marshall a list of subscriptions in case a listener changes depth/cancels.
    final listeners =
        _listeners.values.expand((listeners) => listeners).toList();
    if (error == null) {
      for (var listener in listeners)
        if (listener._onData != null) listener._onData!(t!);
    } else {
      // Exception
      for (var listener in listeners)
        if (listener._onError != null) listener._onError!(error);
    }
  }

  void _maybeEvalF(bool noChangeComparison, dynamic old, dynamic neww) {
    if (_numListeners == 0) {
      _suppressedEvalDueToNoListener = true;
      return;
    }
    if (!noChangeComparison && old == neww) return;
    _evalF();
  }

  void _removeListener(ComputedSubscription<T> sub) {
    final listenersOfDepth = _listeners[sub._creator?.depth ?? 0]!;
    assert(listenersOfDepth.remove(sub));
    _numListeners--;
    if (_numListeners == 0) {
      // cancel subscriptions to all upstreams & remove them from the context (bonus: allow the user to specify a duration before doing that)
    }
  }

  void _addListenerInternal(int depth, dynamic sub) {
    // VERY internal method. Use with great care.
    _listeners.putIfAbsent(depth, (() => <ComputedSubscription<T>>{})).add(sub);
    _numListeners++;
  }

  ComputedSubscription<T> _listen<TT>(
      ComputedImpl<TT>? caller, int callerDepth, void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final sub = ComputedSubscription<T>(this, caller, onData, onError);
    if (_numListeners == 0 && _suppressedEvalDueToNoListener) {
      try {
        _evalF();
        // Might set lastResult, won't notify the listener just yet (as that is against the Stream contract)
      } on NoValueException {}
    }
    _listeners
        .putIfAbsent(callerDepth, (() => <ComputedSubscription<T>>{}))
        .add(sub);
    _numListeners++;
    if (_hasLastResult && onData != null) {
      scheduleMicrotask(() {
        onData(_lastResult!);
      });
    }
    return sub;
  }

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _listen(
        null,
        0, // Downstream Computed-s don't use this method, so pass a 0 as the depth
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError);
  }
}
