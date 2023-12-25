import 'dart:async';

import '../computed.dart';
import 'data_source_subscription.dart';
import 'sync_zone.dart';

class _Token {
  _Token();
}

final _isComputedZone = _Token();

class _ValueOrException<T> {
  final bool _isValue;
  Object? _exc;
  StackTrace? _st;
  T? _value;

  _ValueOrException.value(this._value) : _isValue = true;
  _ValueOrException.exc(this._exc, this._st) : _isValue = false;

  T get value {
    if (_isValue) return _value as T;
    throw _exc!;
  }

  bool shouldNotifyMemoized(_ValueOrException<T>? other) {
    return (_isValue != other?._isValue) ||
        (_isValue && _value != other?._value) ||
        (!_isValue && _exc != other?._exc);
  }
}

class _RouterValueOrException<T> {
  final ComputedImpl<T> _router;
  _ValueOrException<T>? _voe;

  _RouterValueOrException(this._router, this._voe);
}

class _DataSourceAndSubscription<T> {
  final Object _ds;
  _Token? _lastEmit;
  final DataSourceSubscription<T> _dss;

  _DataSourceAndSubscription(this._ds, this._lastEmit, this._dss);
}

class _ComputedSubscriptionImpl<T> implements ComputedSubscription<T> {
  final ComputedImpl<T> _node;
  void Function(T event)? _onData;
  Function? _onError;

  _ComputedSubscriptionImpl(this._node, this._onData, this._onError);

  @override
  void cancel() {
    _node._removeListener(this);
  }

  @override
  void onData(void Function(T data)? handleData) {
    _onData = handleData;
  }

  @override
  void onError(Function? handleError) {
    _onError = handleError;
  }
}

class _MemoizedValueOrException<T> {
  final bool _memoized;
  final _ValueOrException<T>? _voe;

  _MemoizedValueOrException(this._memoized, this._voe);
}

class GlobalCtx {
  static ComputedImpl? _currentComputation;
  static ComputedImpl get currentComputation {
    if (_currentComputation == null) {
      throw StateError(
          "`use` and `prev` are only allowed inside computations.");
    }
    return _currentComputation!;
  }

  static ComputedImpl? routerFor(Object ds) {
    return _routerExpando[ds]?._router;
  }

  static _RouterValueOrException<T> _maybeCreateRouterFor<T>(
      Object dataSource,
      DataSourceSubscription<T> Function(ComputedImpl<T> router) dss,
      T Function()? currentValue) {
    var rvoe =
        GlobalCtx._routerExpando[dataSource] as _RouterValueOrException<T>?;

    if (rvoe == null) {
      rvoe = _RouterValueOrException(
          ComputedImpl(() {
            if (rvoe!._voe == null) {
              throw NoValueException();
            }
            return rvoe._voe!.value;
          }, true, false),
          currentValue != null
              ? _ValueOrException.value(currentValue())
              : null);
      GlobalCtx._routerExpando[dataSource] = rvoe;
      // Run the subscriber outside the sync zone
      final zone = Zone.current[_isComputedZone] == true
          ? Zone.current.parent!
          : Zone.current;
      final sub = zone.run(() => dss(rvoe!._router));

      rvoe._router._dss ??= _DataSourceAndSubscription<T>(dataSource,
          currentValue != null ? GlobalCtx._currentUpdate : null, sub);
      if (currentValue != null) rvoe._router._evalF();
    }

    return rvoe;
  }

  // For each data source, have a "router", which is a computation that returns the
  // value, or throws the error, produced by the data source.
  // This allows most of the logic to only deal with upstream computations.
  static final _routerExpando = Expando<_RouterValueOrException>('computed');

  static var _currentUpdate = _Token(); // Guaranteed to be unique thanks to GC

  static var _reacting = false;
}

class ComputedImpl<T> {
  _DataSourceAndSubscription<T>? _dss;

  // Whether this node is memoized.
  // Always true for routers, which might have both memoized (.use)
  // and non-memoized (.react) listeners.
  final bool _memoized;
  final bool _async;
  _Token? _lastUpdate;

  bool get _novalue => _lastResult == null;
  _ValueOrException<T>? _lastResult;
  _ValueOrException<T>? _prevResult;
  T? _initialPrev;
  Map<ComputedImpl, _MemoizedValueOrException>?
      _lastResultfulUpstreamComputations;
  var _lastUpstreamComputations = <ComputedImpl, _MemoizedValueOrException>{};

  bool get _computing => _curUpstreamComputations != null;
  Object? _reactSuppressedException;
  StackTrace? _reactSuppressedExceptionStackTrace;
  Map<ComputedImpl, _MemoizedValueOrException>? _curUpstreamComputations;

  final _memoizedDownstreamComputations = <ComputedImpl>{};
  final _nonMemoizedDownstreamComputations = <ComputedImpl>{};

  final _listeners = <_ComputedSubscriptionImpl<T>>{};

  var _dirty = false;

  T get prev {
    final caller = GlobalCtx.currentComputation;
    if (caller == this) {
      if (_prevResult == null && _initialPrev == null) throw NoValueException();
      return (_prevResult?.value ?? _initialPrev)!;
    } else {
      if (caller._lastResult == null) throw NoValueException();
      final mvoe = caller._lastResultfulUpstreamComputations![this];
      if (mvoe?._voe == null) {
        throw NoValueException();
      }
      return mvoe!._voe!.value;
    }
  }

  T Function() _f;
  final T Function() _origF;

  ComputedImpl(this._f, this._memoized, this._async) : _origF = _f;

  static ComputedImpl<T> withPrev<T>(
      T Function(T prev) f, T initialPrev, bool memoized, bool async) {
    late ComputedImpl<T> c;
    c = ComputedImpl<T>(
        () => f(c._prevResult?.value ?? initialPrev), memoized, async);
    c._initialPrev = initialPrev;

    return c;
  }

  void onDataSourceData(T data) {
    if (_dss == null) return;
    GlobalCtx._currentUpdate = _Token();
    _dss!._lastEmit = GlobalCtx._currentUpdate;
    final rvoe =
        GlobalCtx._routerExpando[_dss!._ds] as _RouterValueOrException<T>;
    if (rvoe._voe == null ||
        !rvoe._voe!._isValue ||
        rvoe._voe!._value != data) {
      // Update the global last value cache
      rvoe._voe = _ValueOrException<T>.value(data);
    } else if (_nonMemoizedDownstreamComputations.isEmpty) {
      return;
    }

    _rerunGraph();
  }

  void onDataSourceError(Object err) {
    if (_dss == null) return;
    GlobalCtx._currentUpdate = _Token();

    _dss!._lastEmit = GlobalCtx._currentUpdate;
    final rvoe =
        GlobalCtx._routerExpando[_dss!._ds] as _RouterValueOrException<T>;
    if (rvoe._voe == null || rvoe._voe!._isValue || rvoe._voe!._exc != err) {
      // Update the global last value cache
      rvoe._voe = _ValueOrException<T>.exc(err, StackTrace.current);
    } else if (_nonMemoizedDownstreamComputations.isEmpty) {
      return;
    }

    _rerunGraph();
  }

  ComputedSubscription<T> listen(
      void Function(T event)? onData, Function? onError) {
    final sub = _ComputedSubscriptionImpl<T>(this, onData, onError);
    if (_novalue) {
      try {
        _evalF();
        // Might set lastResult, won't notify the listener just yet (as that is against the Stream contract)
      } on NoValueException {
        // It is fine if we don't have a value yet
      }
    }
    _listeners.add(sub);
    if (!_novalue) {
      if (!_lastResult!._isValue) {
        final lastError = _lastResult!._exc!;
        final lastST = _lastResult!._st!;
        if (onError != null) {
          scheduleMicrotask(() {
            onError(lastError);
          });
        } else if (_listeners.length == 1) {
          Zone.current.handleUncaughtError(lastError, lastST);
        }
      } else if (_lastResult!._isValue && onData != null) {
        final lastResult = _lastResult!._value as T;
        scheduleMicrotask(() {
          onData(lastResult);
        });
      }
    }
    return sub;
  }

  DT dataSourceUse<DT>(
      Object dataSource,
      DataSourceSubscription<DT> Function(ComputedImpl<DT> router) dss,
      DT Function()? currentValue) {
    final rvoe =
        GlobalCtx._maybeCreateRouterFor<DT>(dataSource, dss, currentValue);

    return rvoe._router.use;
  }

  DT dataSourcePrev<DT>(Object dataSource) {
    final rvoe =
        GlobalCtx._routerExpando[dataSource] as _RouterValueOrException<DT>?;
    if (rvoe == null) {
      throw NoValueException();
    }
    return rvoe._router.prev;
  }

  DT dataSourcePrevOr<DT>(Object dataSource, DT or) {
    try {
      return dataSourcePrev(dataSource);
    } on NoValueException {
      return or;
    }
  }

  void dataSourceReact<DT>(
      Object dataSource,
      DataSourceSubscription<DT> Function(ComputedImpl<DT> router) dss,
      DT Function()? currentValue,
      void Function(DT) onData,
      void Function(Object)? onError) {
    final rvoe =
        GlobalCtx._maybeCreateRouterFor<DT>(dataSource, dss, currentValue);

    // Routers don't call .react on data sources, they call .use
    assert(rvoe._router != this);

    rvoe._router._react(onData, onError);
  }

  void mock(T Function() mock) {
    _f = mock;
    GlobalCtx._currentUpdate = _Token();
    _rerunGraph();
  }

  void unmock() {
    _f = _origF;
    GlobalCtx._currentUpdate = _Token();
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
      try {
        if (cur._memoizedDownstreamComputations.isEmpty &&
            cur._nonMemoizedDownstreamComputations.isEmpty &&
            cur._listeners.isEmpty) {
          continue;
        }
        if (cur._lastUpdate != GlobalCtx._currentUpdate) {
          try {
            if (cur == this) {
              _evalF();
            } else {
              cur.onDependencyUpdated();
            }
          } on NoValueException {
            // Do not evaluate the children
            continue;
          }
        }
        assert(cur._lastUpdate == GlobalCtx._currentUpdate);
        for (var down in [
          ...cur._memoizedDownstreamComputations,
          ...cur._nonMemoizedDownstreamComputations
        ]) {
          if (!done.contains(down)) {
            var nud = numUnsatDep[down];
            if (nud == null) {
              nud = 0;
              for (var up in down._lastUpstreamComputations.keys) {
                nud = nud! + (up._dirty ? 1 : 0);
              }
            } else {
              assert(nud > 0);
              nud--;
            }
            if (nud == 0) {
              noUnsatDep.add(down);
            } else {
              numUnsatDep[down] = nud!;
            }
          }
        }
      } finally {
        done.add(cur);
      }
    }
  }

  void onDependencyUpdated() {
    if (_lastResult == null || _dss != null) {
      _evalF();
      return;
    }
    if (!_dirty) {
      _lastUpdate = GlobalCtx._currentUpdate;
    } else {
      _evalF();
    }
  }

  T _evalFInZone() {
    final Zone zone;
    final inSyncZone = Zone.current[_isComputedZone] != null;
    if (_async) {
      zone = inSyncZone ? Zone.current.parent! : Zone.current;
    } else {
      zone = inSyncZone
          ? Zone.current
          : Zone.current.fork(
              specification: computedZone, zoneValues: {_isComputedZone: true});
    }

    return zone.run(_f);
  }

  _ValueOrException<T> _evalFGuarded() {
    try {
      final result = _ValueOrException.value(_evalFInZone());
      if (_reactSuppressedException != null) {
        // Throw it here
        final exc = _reactSuppressedException!;
        final st = _reactSuppressedExceptionStackTrace!;
        _reactSuppressedException = null;
        _reactSuppressedExceptionStackTrace = null;
        Error.throwWithStackTrace(exc, st);
      }
      return result;
    } catch (e, s) {
      return _ValueOrException.exc(e, s);
    }
  }

  // Also notifies the listeners (but not downstream computations) if necessary
  void _evalF() {
    const idempotencyFailureMessage =
        "Computed expressions must be purely functional. Please use listeners for side effects. For computations creating asynchronous operations, make sure to use `Computed.async`.";
    _dirty = false;
    final oldComputation = GlobalCtx._currentComputation;
    var gotNVE = false;
    bool shouldNotify = false;
    try {
      final oldPrevResult = _prevResult;
      final oldUpstreamComputations = _lastUpstreamComputations;
      _prevResult = _lastResult;
      _curUpstreamComputations = {};
      GlobalCtx._currentComputation = this;
      var newResult = _evalFGuarded();
      if (!_async &&
          (newResult._isValue || newResult._exc is NoValueException)) {
        // Run f() once again and see if it behaves identically
        bool ensureIdempotent() {
          final idempotentResult = _evalFGuarded();
          if (newResult._isValue) {
            return idempotentResult._isValue &&
                idempotentResult._value == newResult._value;
          } else {
            assert(newResult._exc is NoValueException);
            return !idempotentResult._isValue &&
                idempotentResult._exc is NoValueException;
          }
        }

        try {
          assert(ensureIdempotent(), idempotencyFailureMessage);
        } on AssertionError catch (e, s) {
          newResult = _ValueOrException.exc(e, s);
        }
      }

      if (!newResult._isValue && newResult._exc is NoValueException) {
        gotNVE = true;
      } else {
        _lastResult = newResult;
      }

      shouldNotify = !gotNVE &&
          (!_memoized ||
              (_prevResult?.shouldNotifyMemoized(_lastResult) ?? true));
      if (gotNVE || shouldNotify) {
        // Commit the changes to the DAG
        for (var e in _curUpstreamComputations!.entries) {
          final up = e.key;
          up._addDownstreamComputation(this, e.value._memoized);
        }
        final oldDiffNew = _lastUpstreamComputations.keys
            .toSet()
            .difference(_curUpstreamComputations!.keys.toSet());
        for (var up in oldDiffNew) {
          up._removeDownstreamComputation(this);
        }
      }

      // Even if f() throws NoValueException
      // So that we can memoize that f threw NoValueException
      // when ran with a specific set of dependencies, for example.
      _lastUpstreamComputations = _curUpstreamComputations!;
      _curUpstreamComputations = null;
      // Bookkeep the fact the we ran/tried to run this computation
      // so that we can unlock its downstream during the DAG walk
      _lastUpdate = GlobalCtx._currentUpdate;

      if (gotNVE) {
        Error.throwWithStackTrace(newResult._exc!, newResult._st!);
      } else {
        for (var down in _nonMemoizedDownstreamComputations) {
          if (!down._computing) down._dirty = true;
        }
        if (shouldNotify) {
          _lastResultfulUpstreamComputations = _lastUpstreamComputations;
          for (var down in _memoizedDownstreamComputations) {
            if (!down._computing) down._dirty = true;
          }
        } else {
          // If the result of the computation is the same as the last time,
          // undo its effects on the node state to preserve prev values.
          _lastResult = _prevResult;
          _prevResult = oldPrevResult;
          _lastUpstreamComputations = oldUpstreamComputations;
        }
      }
    } finally {
      if (shouldNotify) {
        GlobalCtx._currentComputation = null;
        _notifyListeners();
      }
      GlobalCtx._currentComputation = oldComputation;
    }
  }

  void _notifyListeners() {
    if (!_lastResult!._isValue) {
      // Exception
      var onErrorNotified = false;
      for (var listener in _listeners) {
        if (listener._onError != null) {
          onErrorNotified = true;
          listener._onError!(_lastResult!._exc!);
        }
      }
      if (_listeners.isNotEmpty && !onErrorNotified) {
        // Propagate to the Zone
        Zone.current.handleUncaughtError(_lastResult!._exc!, _lastResult!._st!);
      }
    } else {
      for (var listener in _listeners) {
        if (listener._onData != null) {
          listener._onData!(_lastResult!._value as T);
        }
      }
    }
  }

  void _addDownstreamComputation(ComputedImpl down, bool memoized) {
    if (memoized) {
      // Only routers can have non-memoized downstream computations
      if (_dss != null) {
        // Make sure a downstream computation cannot be subscribed as both memoizing and non-memoizing
        if (!_nonMemoizedDownstreamComputations.contains(down)) {
          _memoizedDownstreamComputations.add(down);
        }
      } else {
        this._memoizedDownstreamComputations.add(down);
      }
    } else {
      // Make sure a downstream computation cannot be subscribed as both memoizing and non-memoizing
      _memoizedDownstreamComputations.remove(down);
      _nonMemoizedDownstreamComputations.add(down);
    }
  }

  void _removeDataSourcesAndUpstreams() {
    for (var upComp in _lastUpstreamComputations.keys) {
      upComp._removeDownstreamComputation(this);
    }
    _lastUpstreamComputations = {};
    if (_dss != null) {
      _dss!._dss.cancel();
      // Remove ourselves from the expando
      GlobalCtx._routerExpando[_dss!._ds] = null;
      _dss = null;
    }

    _lastResult = null; // So that we re-run the next time we are subscribed to
    _lastUpdate = null;
    _lastResultfulUpstreamComputations = null;
  }

  void _removeDownstreamComputation(ComputedImpl c) {
    bool removed = _memoizedDownstreamComputations.remove(c) ||
        _nonMemoizedDownstreamComputations.remove(c);
    assert(removed, "Corrupted internal state");
    if (_memoizedDownstreamComputations.isEmpty &&
        _nonMemoizedDownstreamComputations.isEmpty &&
        _listeners.isEmpty) {
      _removeDataSourcesAndUpstreams();
    }
  }

  void _removeListener(ComputedSubscription<T> sub) {
    _listeners.remove(sub);
    if (_memoizedDownstreamComputations.isEmpty &&
        _nonMemoizedDownstreamComputations.isEmpty &&
        _listeners.isEmpty) {
      _removeDataSourcesAndUpstreams();
    }
  }

  void _react(void Function(T) onData, void Function(Object)? onError) {
    // Only routers can be .react-ed to
    // As otherwise the meaning of .prev becomes ambiguous
    assert(_dss != null);
    final caller = GlobalCtx.currentComputation;
    if (GlobalCtx._reacting) {
      throw StateError("`use` and `react` not allowed inside react callbacks.");
    }
    // Make sure the caller is subscribed
    caller._curUpstreamComputations![this] =
        _MemoizedValueOrException(false, _lastResult);

    if (_dss!._lastEmit != GlobalCtx._currentUpdate) {
      // Don't call the functions
      return;
    }

    GlobalCtx._reacting = true;
    try {
      if (_lastResult!._isValue) {
        onData(_lastResult!._value as T);
      } else if (onError != null) {
        onError(_lastResult!._exc as Object);
      } else {
        // Do not throw the exception here,
        // as this might cause other .react/.use-s to get skipped
        caller._reactSuppressedException ??= _lastResult!._exc;
        caller._reactSuppressedExceptionStackTrace ??= _lastResult!._st;
      }
    } finally {
      GlobalCtx._reacting = false;
    }
  }

  void _checkCycle(ComputedImpl caller) {
    final seen = <ComputedImpl>{};
    void dfs(ComputedImpl c) {
      if (seen.contains(c)) return;
      seen.add(c);
      seen.addAll(c._lastUpstreamComputations.keys);
      for (var up in c._lastUpstreamComputations.keys) {
        dfs(up);
      }
    }

    dfs(this);

    if (seen.contains(caller)) throw CyclicUseException();
  }

  T get use {
    if (_computing) throw CyclicUseException();

    final caller = GlobalCtx.currentComputation;
    if (GlobalCtx._reacting) {
      throw StateError("`use` and `react` not allowed inside react callbacks.");
    }
    if (caller._curUpstreamComputations![this] == null) {
      // Check for cycles
      _checkCycle(caller);
      // Make sure the caller is subscribed
      caller._curUpstreamComputations![this] = _MemoizedValueOrException(
          // If the caller is subscribed in a non-memoizing way, keep it.
          caller._curUpstreamComputations![this]?._memoized ?? true,
          _lastResult);
    }

    if (_lastUpdate != GlobalCtx._currentUpdate && _lastResult == null) {
      _evalF();
    }

    if (_lastResult == null) throw NoValueException();

    return _lastResult!.value;
  }
}
