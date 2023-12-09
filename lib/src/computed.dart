import 'dart:async';

import '../computed.dart';
import 'data_source_subscription.dart';

class _UpdateToken {
  _UpdateToken();
}

class _ValueOrException<T> {
  final bool _isValue;
  Object? _exc;
  T? _value;

  _ValueOrException.value(T value)
      : _isValue = true,
        _value = value;
  _ValueOrException.exc(Object exc)
      : _isValue = false,
        _exc = exc;

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
  _UpdateToken? _lastEmit;
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
      bool hasCurrentValue,
      T? currentValue) {
    var rvoe =
        GlobalCtx._routerExpando[dataSource] as _RouterValueOrException<T>?;

    if (rvoe == null) {
      rvoe = _RouterValueOrException(
          ComputedImpl(() {
            if (rvoe!._voe == null) {
              throw NoValueException();
            }
            return rvoe._voe!.value;
          }, true),
          hasCurrentValue ? _ValueOrException.value(currentValue as T) : null);
      GlobalCtx._routerExpando[dataSource] = rvoe;
      rvoe._router._dss ??= _DataSourceAndSubscription<T>(dataSource,
          hasCurrentValue ? GlobalCtx._currentUpdate : null, dss(rvoe._router));
      if (hasCurrentValue) rvoe._router._evalF();
    }

    return rvoe;
  }

  // For each data source, have a "router", which is a computation that returns the
  // value, or throws the error, produced by the data source.
  // This allows most of the logic to only deal with upstream computations.
  static final _routerExpando = Expando<_RouterValueOrException>('computed');

  static var _currentUpdate =
      _UpdateToken(); // Guaranteed to be unique thanks to GC
}

class ComputedImpl<T> {
  _DataSourceAndSubscription<T>? _dss;

  // Whether this node is memoized.
  // Always true for routers, which might have both memoized (.use)
  // and non-memoized (.react) listeners.
  final bool _memoized;
  _UpdateToken? _lastUpdate;

  bool get _novalue => _lastResult == null;
  _ValueOrException<T>? _lastResult;
  _ValueOrException<T>? _prevResult;
  T? _initialPrev;
  Map<ComputedImpl, _MemoizedValueOrException>?
      _lastResultfulUpstreamComputations;
  var _lastUpstreamComputations = <ComputedImpl, _MemoizedValueOrException>{};

  bool get _computing => _curUpstreamComputations != null;
  bool _reacting = false;
  Object? _reactSuppressedException;
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

  ComputedImpl(this._f, this._memoized) : _origF = _f;

  static ComputedImpl<T> withPrev<T>(
      T Function(T prev) f, T initialPrev, bool memoized) {
    late ComputedImpl<T> c;
    c = ComputedImpl<T>(() => f(c._prevResult?.value ?? initialPrev), memoized);
    c._initialPrev = initialPrev;

    return c;
  }

  void onDataSourceData(T data) {
    if (_dss == null) return;
    GlobalCtx._currentUpdate = _UpdateToken();
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
    GlobalCtx._currentUpdate = _UpdateToken();

    _dss!._lastEmit = GlobalCtx._currentUpdate;
    final rvoe =
        GlobalCtx._routerExpando[_dss!._ds] as _RouterValueOrException<T>;
    if (rvoe._voe == null || rvoe._voe!._isValue || rvoe._voe!._exc != err) {
      // Update the global last value cache
      rvoe._voe = _ValueOrException<T>.exc(err);
    } else if (_nonMemoizedDownstreamComputations.isEmpty) {
      return;
    }

    _rerunGraph();
  }

  ComputedSubscription<T> listen(
      void Function(T event)? onData, Function? onError) {
    if (GlobalCtx._currentComputation != null) {
      throw StateError('`listen` is not allowed inside computations.');
    }
    final sub = _ComputedSubscriptionImpl<T>(this, onData, onError);
    if (_novalue) {
      try {
        _evalF();
        // Might set lastResult, won't notify the listener just yet (as that is against the Stream contract)
      } on NoValueException {
        // It is fine if we don't have a value yet
      } catch (e) {
        // For any other exception,
        // schedule an onError call
        if (onError != null) {
          scheduleMicrotask(() {
            onError(e);
          });
        }
      }
    }
    _listeners.add(sub);
    if (!_novalue) {
      if (!_lastResult!._isValue && onError != null) {
        final lastError = _lastResult!._exc!;
        scheduleMicrotask(() {
          onError(lastError);
        });
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
      bool hasCurrentValue,
      DT? currentValue) {
    final rvoe = GlobalCtx._maybeCreateRouterFor<DT>(
        dataSource, dss, hasCurrentValue, currentValue);

    if (rvoe._router != this) {
      // Subscribe to the router instead
      return rvoe._router.use;
    }
    // We are the router (thus, DT == T)

    if (rvoe._voe == null) {
      throw NoValueException();
    }
    return rvoe._voe!.value;
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
      bool hasCurrentValue,
      DT? currentValue,
      void Function(DT) onData,
      void Function(Object)? onError) {
    final rvoe = GlobalCtx._maybeCreateRouterFor<DT>(
        dataSource, dss, hasCurrentValue, currentValue);

    // Routers don't call .react on data sources, they call .use
    assert(rvoe._router != this);

    rvoe._router._react(onData, onError);
  }

  void mock(T Function() mock) {
    _f = mock;
    GlobalCtx._currentUpdate = _UpdateToken();
    _rerunGraph();
  }

  void unmock() {
    _f = _origF;
    GlobalCtx._currentUpdate = _UpdateToken();
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
              cur._maybeEvalF();
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

  void _maybeEvalF() {
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

  // Also notifies the listeners (but not downstream computations) if necessary
  void _evalF() {
    _dirty = false;
    final oldComputation = GlobalCtx._currentComputation;
    var gotNVE = false;
    try {
      final oldPrevResult = _prevResult;
      final oldUpstreamComputations = _lastUpstreamComputations;
      _prevResult = _lastResult;
      _curUpstreamComputations = {};
      try {
        GlobalCtx._currentComputation = this;
        final newResult = _ValueOrException.value(_f());
        if (_reactSuppressedException != null) {
          // Throw it here
          throw _reactSuppressedException!;
        }
        // If we are the first _evalF in the call stack,
        // run f() a second time to make sure it returns the same result.
        // Nested _evalF-s don't do this to avoid calling
        // deeply nested computations exponentially many times.
        ast() {
          T? f2;
          try {
            f2 = _f();
          } catch (_) {
            return false;
          }
          return f2 == newResult._value;
        }

        assert(ast(),
            "Computed expressions must be purely functional. Please use listeners for side effects.");
        _lastResult = newResult;
      } on NoValueException {
        gotNVE = true;
        // Not much we can do
        // Run the computation once again and make sure
        // it throws NoValueException again
        ast() {
          try {
            _f();
          } on NoValueException {
            // Good
            return true;
          } catch (_) {
            // Pass
          }
          return false;
        }

        assert(ast(),
            "Computed expressions must be purely functional. Please use listeners for side effects.");
        rethrow;
      } catch (e) {
        // Do not re-run f in this path to check for side effects
        // as thrown objects might not implement ==
        _lastResult = _ValueOrException.exc(e);
      } finally {
        _reactSuppressedException = null;
        final shouldNotify =
            _prevResult?.shouldNotifyMemoized(_lastResult) ?? true;
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
        // Even for the non "resultful" case.
        // So that we can memoize that f threw NoValueException
        // when ran with a specific set of dependencies, for example.
        _lastUpstreamComputations = _curUpstreamComputations!;
        _curUpstreamComputations = null;
        // Bookkeep the fact the we ran/tried to run this computation
        // so that we can unlock its downstream during the DAG walk
        _lastUpdate = GlobalCtx._currentUpdate;
      }
      // The "resultful" case (the function either returned or threw an exception other than NoValueException)
      for (var down in _nonMemoizedDownstreamComputations) {
        if (!down._computing) down._dirty = true;
      }
      final shouldNotify =
          _prevResult?.shouldNotifyMemoized(_lastResult) ?? true;
      if (!_memoized || shouldNotify) {
        _lastResultfulUpstreamComputations = _lastUpstreamComputations;
        for (var down in _memoizedDownstreamComputations) {
          if (!down._computing) down._dirty = true;
        }
        _notifyListeners();
      } else {
        // If the result of the computation is the same as the last time,
        // undo its effects on the node state to preserve prev values.
        _lastResult = _prevResult;
        _prevResult = oldPrevResult;
        _lastUpstreamComputations = oldUpstreamComputations;
      }
    } finally {
      GlobalCtx._currentComputation = oldComputation;
    }
  }

  void _notifyListeners() {
    if (!_lastResult!._isValue) {
      // Exception
      for (var listener in _listeners) {
        if (listener._onError != null) listener._onError!(_lastResult!._exc!);
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
    assert(_memoizedDownstreamComputations.remove(c) ||
        _nonMemoizedDownstreamComputations.remove(c));
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
    if (caller._reacting) {
      throw StateError("`use` and `react` not allowed inside react callbacks.");
    }
    // Make sure the caller is subscribed
    caller._curUpstreamComputations![this] =
        _MemoizedValueOrException(false, _lastResult);

    if (_dss!._lastEmit != GlobalCtx._currentUpdate) {
      // Don't call the functions
      return;
    }

    caller._reacting = true;
    try {
      if (_lastResult!._isValue) {
        onData(_lastResult!._value as T);
      } else if (onError != null) {
        onError(_lastResult!._exc as Object);
      } else {
        // Do not throw the exception here,
        // as this might cause other .react/.use-s to get skipped
        caller._reactSuppressedException ??= _lastResult!._exc;
      }
    } finally {
      caller._reacting = false;
    }
  }

  T get use {
    if (_computing) throw CyclicUseException();

    final caller = GlobalCtx.currentComputation;
    if (caller._reacting) {
      throw StateError("`use` and `react` not allowed inside react callbacks.");
    }
    // Make sure the caller is subscribed
    caller._curUpstreamComputations![this] = _MemoizedValueOrException(
        // If the caller is subscribed in a non-memoizing way, keep it.
        caller._curUpstreamComputations![this]?._memoized ?? true,
        _lastResult);

    if (_lastUpdate != GlobalCtx._currentUpdate &&
        (_dss == null || _lastResult == null)) {
      // This means that this [use] happened outside the control of [_rerunGraph]
      // so be prudent and force a re-computation.
      // The main benefit is that this helps us detect cyclic dependencies.
      _evalF();
    }

    if (_lastResult == null) throw NoValueException();

    return _lastResult!.value;
  }
}
