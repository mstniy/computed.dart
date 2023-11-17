import 'dart:async';

import '../computed.dart';

class LastValue<T> {
  bool hasValue = false;
  T? lastValue;
}

class LastValueRouter<T> extends LastValue<T> {
  ComputedImpl<T> router;
  LastValueRouter(this.router);
}

class GlobalCtx {
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
    final caller = GlobalCtx.currentComputation;
    return caller.useDataSource(
        s,
        () => s.use,
        (onData) => StreamDataSourceSubscription(s.listen(onData)),
        false,
        null);
  }
}

class ComputedFutureExtensionImpl<T> {
  final Future<T> f;

  ComputedFutureExtensionImpl(this.f);
  T get use {
    final caller = GlobalCtx.currentComputation;
    return caller.useDataSource(
        f,
        () => f.use,
        (onData) => FutureDataSourceSubscription<T>(f, onData, (e) {}),
        false,
        null); // TODO: Handle onError (passthrough)
  }
}

class ComputedStreamSubscription<T> implements StreamSubscription<T> {
  final ComputedImpl<T> _node;
  void Function(T event)? _onData;
  Function? _onError;
  ComputedStreamSubscription(this._node, this._onData, this._onError);
  @override
  Future<E> asFuture<E>([E? futureValue]) {
    throw UnsupportedError(
        'asFuture not supported by Stream subscriptions to Computed'); // Doesn't make much sense in this context
  }

  @override
  Future<void> cancel() async {
    _node._removeListener(this);
  }

  @override
  bool get isPaused => false; // TODO: Allow Computed-s to be paused and resumed

  @override
  void onData(void Function(T data)? handleData) {
    _onData = handleData;
  }

  @override
  void onDone(void Function()? handleDone) {
    // TODO: Have support for done signals
    throw UnimplementedError();
  }

  @override
  void onError(Function? handleError) {
    _onError = handleError;
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    throw UnimplementedError();
  }

  @override
  void resume() {
    throw UnimplementedError();
  }
}

class ComputedStream<T> extends Stream<T> {
  ComputedImpl<T> _parent;

  ComputedStream(this._parent);

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final sub = ComputedStreamSubscription<T>(_parent, onData, onError);
    if (_parent._novalue) {
      try {
        _parent._evalF();
        // Might set lastResult, won't notify the listener just yet (as that is against the Stream contract)
      } on NoValueException {}
    }
    _parent._listeners.add(sub);
    if (!_parent._novalue) {
      if (_parent._lastWasError! && onError != null) {
        final lastError = _parent._lastError!;
        scheduleMicrotask(() {
          onError(lastError);
        });
      } else if (!_parent._lastWasError! && onData != null) {
        final lastResult = _parent._lastResult as T;
        scheduleMicrotask(() {
          onData(lastResult);
        });
      }
    }
    return sub;
  }
}

// Very similar to StreamSubscription
// Except only the parts Computed needs
abstract class DataSourceSubscription<T> {
  Future<void> cancel();

  bool get isPaused;

  void pause([Future<void>? resumeSignal]);
  void resume();
}

class StreamDataSourceSubscription<T> implements DataSourceSubscription<T> {
  final StreamSubscription<T> ss;
  StreamDataSourceSubscription(this.ss);

  @override
  Future<void> cancel() {
    return ss.cancel();
  }

  @override
  bool get isPaused => ss.isPaused;

  @override
  void pause([Future<void>? resumeSignal]) {
    ss.pause(resumeSignal);
  }

  @override
  void resume() {
    ss.resume();
  }
}

class FutureDataSourceSubscription<T> implements DataSourceSubscription<T> {
  final void Function(T data) onValue;
  final Function onError;

  FutureDataSourceSubscription(Future<T> f, this.onValue, this.onError) {
    f.then(this.onValue, onError: this.onError);
  }

  @override
  Future<void> cancel() {
    // We don't need to do anything here.
    // There is no way to cancel a Future and the router will already have lost all its downstream computations.
    return Future.value();
  }

  @override
  // TODO: implement isPaused
  bool get isPaused => throw UnimplementedError();

  @override
  void pause([Future<void>? resumeSignal]) {
    // TODO: implement pause
    throw UnimplementedError();
  }

  @override
  void resume() {
    // TODO: implement resume
    throw UnimplementedError();
  }
}

class ComputedImpl<T> with Computed<T> {
  var _upstreamComputations = <ComputedImpl>{};
  final _downstreamComputations = <ComputedImpl>{};

  var _dataSources = <Object, DataSourceSubscription>{};
  final _listeners = Set<ComputedStreamSubscription<T>>();

  var _novalue = true;
  var _dirty = false;

  bool? _lastWasError;
  T? _lastResult;
  Object? _lastError;
  T get value {
    if (_novalue || _dirty) _evalF();
    if (_lastWasError ?? false) throw _lastError!;
    return _lastResult as T;
  }

  T Function() f;
  final T Function() origF;

  ComputedImpl(this.f) : origF = f;

  DT useDataSource<DT>(
      Object dataSource,
      DT Function() dataSourceUse,
      DataSourceSubscription Function(void Function(DT data) onData) dss,
      bool hasCurrentValue,
      DT? currentValue) {
    // Maintain a global cache of future last values for any new dependencies discovered to use
    var lv = GlobalCtx.lvExpando[dataSource] as LastValueRouter<DT>?;

    if (lv == null) {
      lv = LastValueRouter(ComputedImpl(dataSourceUse));
      lv.hasValue = hasCurrentValue;
      lv.lastValue = currentValue;
      GlobalCtx.lvExpando[dataSource] = lv;
    }
    if (lv.router != this) {
      // Subscribe to the router instead
      return lv.router.use;
    }
    // We are the router
    // Make sure we are subscribed
    _dataSources.putIfAbsent(
        dataSource,
        () => dss((newValue) {
              if (lv!.hasValue && lv.lastValue == newValue) return;
              // Update the global last value cache
              lv.hasValue = true;
              lv.lastValue = newValue;
              _dirty = true;

              _rerunGraph();
            }));

    if (!lv.hasValue) {
      throw NoValueException();
    }
    return lv.lastValue as DT;
  }

  @override
  void mock(T Function() mock) {
    f = mock;
    _dirty = true;
    _rerunGraph();
  }

  @override
  void unmock() {
    f = origF;
    _dirty = true;
    _rerunGraph();
  }

  void _rerunGraph() {
    final numUnsatDep = <ComputedImpl, int>{};
    final noUnsatDep = <ComputedImpl>{this};
    final done = <ComputedImpl>{};

    while (noUnsatDep.isNotEmpty) {
      final cur = noUnsatDep.first;
      noUnsatDep.remove(cur);
      if (done.contains(cur)) continue;
      if (cur._novalue || cur._dirty) {
        if (cur._downstreamComputations.isEmpty && cur._listeners.isEmpty) {
          continue;
        }
        final prevRes = cur._lastResult;
        // Never memoize exceptions
        final wasNoValueOrException =
            cur._novalue || (cur._lastWasError ?? true);
        try {
          cur._evalF();
        } on NoValueException {
          // Do not evaluate the children/notify the listeners
          continue;
        }
        final resultChanged = cur._lastResult != prevRes;
        final shouldNotify = wasNoValueOrException ||
            (cur._lastWasError ?? true) ||
            resultChanged;
        if (shouldNotify) {
          cur._notifyListeners();
        }
      }
      for (var down in cur._downstreamComputations) {
        var nud = numUnsatDep[down];
        if (nud == null) {
          nud = 0;
          for (var up in down._upstreamComputations) {
            nud = nud! +
                (up._dataSources.isEmpty
                    ? 1
                    : ((up._novalue || up._dirty) ? 1 : 0));
          }
        }
        if (cur._dataSources.isEmpty) nud = nud! - 1;
        if (nud == 0) {
          noUnsatDep.add(down);
        } else {
          numUnsatDep[down] = nud!;
        }
      }
      done.add(cur);
    }
  }

  void _evalF() {
    final oldComputation = GlobalCtx._currentComputation;
    try {
      final oldUpstreamComputations = _upstreamComputations;
      final prevRes = _lastResult;
      // Never memoize exceptions
      final wasNoValueOrException = _novalue || (_lastWasError ?? true);
      _upstreamComputations = {};
      try {
        GlobalCtx._currentComputation = this;
        _novalue = false;
        _dirty = false;
        _lastWasError = true;
        _lastError = CyclicUseException();
        _lastResult = f();
        assert(f() == _lastResult,
            "Computed expressions must be purely functional. Please use listeners for side effects.");
        _lastWasError = false;
      } on NoValueException {
        // Not much we can do
        _novalue = true;
        rethrow;
      } on Error {
        _novalue = true;
        rethrow; // Do not propagate errors
      } catch (e) {
        _lastError = e;
      } finally {
        final oldDiffNew =
            oldUpstreamComputations.difference(_upstreamComputations);
        for (var up in oldDiffNew) {
          up._removeDownstreamComputation(this);
        }
        final shouldNotify = wasNoValueOrException ||
            (_lastWasError ?? true) ||
            (_lastResult != prevRes);

        if (shouldNotify) {
          for (var down in _downstreamComputations) {
            down._dirty = true;
          }
        }
      }
    } finally {
      GlobalCtx._currentComputation = oldComputation;
    }
  }

  void _notifyListeners() {
    if (_lastWasError!) {
      // Exception
      for (var listener in _listeners)
        if (listener._onError != null) listener._onError!(_lastError);
    } else {
      for (var listener in _listeners)
        if (listener._onData != null) listener._onData!(_lastResult as T);
    }
  }

  void _removeDataSourcesAndUpstreams() {
    if (_upstreamComputations.isNotEmpty || _dataSources.isNotEmpty) {
      _novalue = true; // So that we re-run the next time we are subscribed to
    }
    for (var upComp in _upstreamComputations)
      upComp._removeDownstreamComputation(this);
    _upstreamComputations.clear();
    for (var strSub in _dataSources.entries) {
      strSub.value.cancel();
      if (GlobalCtx.lvExpando[strSub.key]?.router == this) {
        // If we are the router for this stream, remove ourselves from the expando
        GlobalCtx.lvExpando[strSub.key] = null;
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

  void _removeListener(ComputedStreamSubscription<T> sub) {
    _listeners.remove(sub);
    if (_downstreamComputations.isEmpty && _listeners.isEmpty) {
      _removeDataSourcesAndUpstreams();
    }
  }

  T get use {
    final caller = GlobalCtx.currentComputation;
    // Make sure the caller is subscribed
    caller._upstreamComputations.add(this);
    this._downstreamComputations.add(caller);

    return value;
  }

  Stream<T> get asStream {
    return ComputedStream(this);
  }
}