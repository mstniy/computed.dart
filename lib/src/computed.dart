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

class ComputedImpl<T> implements Computed<T> {
  final _upstreamComputations = <ComputedImpl>{};
  final _downstreamComputations = <ComputedImpl>{};

  final _dataSources = <Object, DataSourceSubscription>{};
  final _listeners = Set<ComputedStreamSubscription<T>>();

  var _dirty = true;

  bool? _lastWasError;
  T? _lastResult;
  Object? _lastError;
  T get value {
    if (_dirty) _evalF();
    if (_lastWasError ?? false) throw _lastError!;
    return _lastResult as T;
  }

  T Function() f;

  ComputedImpl(this.f);

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

              _rerunGraph();
            }));

    if (!lv.hasValue) {
      throw NoValueException();
    }
    return lv.lastValue as DT;
  }

  @override
  void fix(T value) {
    f = () => value;
    if (_dirty || (_lastWasError ?? true) || _lastResult != value) {
      _rerunGraph();
    }
  }

  @override
  void fixException(Object e) {
    f = () => throw e;
    _rerunGraph();
  }

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
      final prevRes = cur._lastResult;
      // Never memoize exceptions
      final wasDirtyOrException = cur._dirty || (cur._lastWasError ?? true);
      cur._evalF();
      final resultChanged = cur._lastResult != prevRes;
      final shouldNotify =
          wasDirtyOrException || (cur._lastWasError ?? true) || resultChanged;
      if (shouldNotify) {
        cur._notifyListeners();
      }
      for (var down in cur._downstreamComputations) {
        if (shouldNotify) resultDirty.add(down);
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
    final oldComputation = GlobalCtx._currentComputation;
    try {
      GlobalCtx._currentComputation = this;
      _lastResult = f();
      assert(f() == _lastResult,
          "Computed expressions must be purely functional. Please use listeners for side effects.");
      _lastError = null;
      _lastWasError = false;
      _dirty = false;
      // cancel subscriptions to unused streams & remove them from the context (bonus: allow the user to specify a duration before doing that)
      // except if this computation has been [fix] ed.
    } on NoValueException catch (e) {
      // Not much we can do
      throw e;
    } on Error catch (e) {
      throw e; // Do not propagate errors
    } catch (e) {
      _lastResult = null;
      _lastError = e;
      _lastWasError = true;
      _dirty = false;
    } finally {
      GlobalCtx._currentComputation = oldComputation;
    }
  }

  void _notifyListeners() {
    if (_lastError == null) {
      for (var listener in _listeners)
        if (listener._onData != null) listener._onData!(_lastResult as T);
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
    // Make sure we are computed
    if (_dirty) _evalF();
    assert(!_dirty);

    return value;
  }

  Stream<T> get asStream {
    return ComputedStream(this);
  }
}
