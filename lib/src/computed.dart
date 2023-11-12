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
  // TODO: Avoid storing a ref to the last value in the expando, move it to the router instead
  static final lvExpando = Expando<LastValueRouter>('computed_lv');
}

class ComputedStreamResolverImpl implements ComputedStreamResolver {
  final ComputedImpl _parent;
  ComputedStreamResolverImpl(this._parent);
  T call<T>(Stream<T> s) {
    if (s is ComputedImpl<T>) {
      // Make sure we are subscribed
      _parent._upstreamComputations.add(s);
      s._downstreamComputations.add(this._parent);
      // Make sure the upstream has been computed
      if (s._dirty) s._evalF();
      assert(s._evaluated);

      if (s._lastWasError!) // TODO: Make this logic into a getter that throws
        throw s._lastError!;
      else
        return s._lastResult!;
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
      _parent._dataSources.putIfAbsent(
          s,
          () => s.listen((newValue) {
                if (lv!.hasValue && lv.lastValue == newValue) return;
                // Update the global last value cache
                lv.hasValue = true;
                lv.lastValue = newValue;
                _parent._rerunGraph();
              })); // Handle onError (passthrough), onDone (close subscriptions to upstreams)
      if (!lv.hasValue) {
        throw NoValueException();
      }
      return lv.lastValue!;
    }
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

class ComputedImpl<T> extends Stream<T> implements Computed<T> {
  final _upstreamComputations = <ComputedImpl>{};
  final _downstreamComputations = <ComputedImpl>{};

  final _dataSources = <Stream, StreamSubscription>{};
  final _listeners = Set<ComputedSubscription<T>>();

  var _dirty = true;

  var _evaluated = false;
  bool get evaluated => _evaluated;
  bool? _lastWasError;
  bool? get lastWasError => _lastWasError;
  T? _lastResult;
  Object? _lastError;
  T? get lastResult => _lastResult;
  Object? get lastError => _lastError;

  final T Function(ComputedStreamResolver ctx) f;

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
      final prevRes = cur.lastResult;
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
    _dirty = false;
    try {
      _lastResult = f(ComputedStreamResolverImpl(this));
      _lastError = null;
      _lastWasError = false;
      _evaluated = true;
      // cancel subscriptions to unused streams & remove them from the context (bonus: allow the user to specify a duration before doing that)
    } on NoValueException catch (e) {
      // Not much we can do
      throw e;
    } catch (e) {
      _lastResult = null;
      _lastError = e;
      _lastWasError = true;
      _evaluated = true;
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
    for (var sub in _dataSources.values) sub.cancel();
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

  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final sub = ComputedSubscription<T>(this, onData, onError);
    if (_dirty) {
      try {
        _evalF();
        // Might set lastResult, won't notify the listener just yet (as that is against the Stream contract)
      } on NoValueException {}
    }
    _listeners.add(sub);
    if (_evaluated) {
      if (_lastWasError! && onError != null) {
        scheduleMicrotask(() {
          onError(_lastError!);
        });
      } else if (!_lastWasError! && onData != null) {
        scheduleMicrotask(() {
          onData(_lastResult!);
        });
      }
    }
    return sub;
  }
}
