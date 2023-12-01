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

  bool shouldNotifyMemoized(_ValueOrException<T> other) {
    return _isValue != other._isValue ||
        (_isValue && _value != other._value) ||
        (!_isValue && _exc != other._exc);
  }
}

class _RouterValueOrException<T> {
  final ComputedImpl<T> _router;
  _ValueOrException<T>? _voe;

  _RouterValueOrException(this._router, this._voe);
}

class _DataSourceAndSubscription<T> {
  final Object _ds;
  final DataSourceSubscription<T> _dss;

  _DataSourceAndSubscription(this._ds, this._dss);
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

class GlobalCtx {
  static ComputedImpl? _currentComputation;
  static ComputedImpl get currentComputation {
    if (_currentComputation == null) {
      throw StateError(
          "`use` and `prev` are only allowed inside Computed expressions.");
    }
    return _currentComputation!;
  }

  static ComputedImpl? routerFor(Object ds) {
    return _routerExpando[ds]?._router;
  }

  // For each data source, have a "router", which is a computation that returns the
  // value, or throws the error, produced by the data source.
  // This allows most of the logic to only deal with upstream computations.
  static final _routerExpando = Expando<_RouterValueOrException>('computed');

  static _UpdateToken? _currentUpdate;
  // Note that _currentUpdateTriggerer might be null even if
  // _currentUpdate is not if the current run is triggered by a (un)mock
  // on a computation
  static Object? _currentUpdateTriggerer;
}

class ComputedImpl<T> with Computed<T> {
  _DataSourceAndSubscription<T>? _dss;

  _UpdateToken? _lastUpdate;

  bool get _novalue => _lastResult == null;
  _ValueOrException<T>? _lastResult;
  _ValueOrException<T>? _prevResult;
  Map<ComputedImpl, _ValueOrException?>? _lastResultfulUpstreamComputations;
  var _lastUpstreamComputations = <ComputedImpl, _ValueOrException?>{};

  bool get _computing => _curUpstreamComputations != null;
  Map<ComputedImpl, _ValueOrException?>? _curUpstreamComputations;

  final _memoizedDownstreamComputations = <ComputedImpl>{};
  final _nonMemoizedDownstreamComputations = <ComputedImpl>{};

  final _listeners = <_ComputedSubscriptionImpl<T>>{};

  var _dirty = false;

  @override
  T get prev {
    final caller = GlobalCtx.currentComputation;
    if (caller == this) {
      if (_prevResult == null) throw NoValueException();
      return _prevResult!.value;
    } else {
      if (caller._lastResult == null) throw NoValueException();
      final voe = caller._lastResultfulUpstreamComputations![this];
      if (voe == null) {
        throw NoValueException();
      }
      return voe.value;
    }
  }

  T Function() _f;
  final T Function() _origF;

  ComputedImpl(this._f) : _origF = _f;

  static ComputedImpl<T> withPrev<T>(T Function(T prev) f, T initialPrev) {
    late ComputedImpl<T> c;
    c = ComputedImpl<T>(() {
      c._prevResult ??= _ValueOrException.value(initialPrev);
      return f(c._prevResult!.value);
    });

    return c;
  }

  void onDataSourceData(T data) {
    if (_dss == null) return;
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

  @override
  ComputedSubscription<T> listen(
      void Function(T event)? onData, Function? onError) {
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
      DT Function() dataSourceUser,
      DataSourceSubscription<DT> Function(ComputedImpl<DT> router) dss,
      bool hasCurrentValue,
      DT? currentValue,
      // TODO: Remove the memoized parameter
      bool memoized) {
    var rvoe =
        GlobalCtx._routerExpando[dataSource] as _RouterValueOrException<DT>?;

    if (rvoe == null) {
      rvoe = _RouterValueOrException(ComputedImpl(dataSourceUser),
          hasCurrentValue ? _ValueOrException.value(currentValue as DT) : null);
      GlobalCtx._routerExpando[dataSource] = rvoe;
      rvoe._router._dss ??=
          _DataSourceAndSubscription<DT>(dataSource, dss(rvoe._router));
    }

    if (rvoe._router != this) {
      // Subscribe to the router instead
      return rvoe._router._use(memoized);
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

  void dataSourceReact<DT>(
      Object dataSource,
      DT Function() dataSourceUser,
      DataSourceSubscription<DT> Function(ComputedImpl<DT> router) dss,
      bool hasCurrentValue,
      DT? currentValue,
      void Function(DT) onData,
      void Function(Object)? onError) {
    DT value;
    try {
      value = dataSourceUse<DT>(dataSource, dataSourceUser, dss,
          hasCurrentValue, currentValue, false);
    } on NoValueException {
      // Don't run the functions
      return;
    } catch (e) {
      if (onError != null) onError(e);
      return;
    }
    onData(value);
  }

  @override
  void mock(T Function() mock) {
    _f = mock;
    _rerunGraph();
  }

  @override
  void unmock() {
    _f = _origF;
    _rerunGraph();
  }

  void _rerunGraph() {
    GlobalCtx._currentUpdate =
        _UpdateToken(); // Guaranteed to be unique thanks to GC
    GlobalCtx._currentUpdateTriggerer = _dss?._ds;
    try {
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
    } finally {
      GlobalCtx._currentUpdate = null;
      GlobalCtx._currentUpdateTriggerer = null;
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
    try {
      final oldPrevResult = _prevResult;
      final oldUpstreamComputations = _lastUpstreamComputations;
      _prevResult = _lastResult;
      _curUpstreamComputations = {};
      try {
        GlobalCtx._currentComputation = this;
        final newResult = _ValueOrException.value(_f());
        if (oldComputation == null) {
          // If we are the first _evalF in the call stack,
          // run f() a second time to make sure it returns the same result.
          // Nested _evalF-s don't do this to avoid calling
          // deeply nested computations exponentially many times.
          assert(() {
            T? f2;
            try {
              f2 = _f();
            } catch (_) {
              return false;
            }
            return f2 == newResult._value;
          }(),
              "Computed expressions must be purely functional. Please use listeners for side effects.");
        }
        _lastResult = newResult;
      } on NoValueException {
        // Not much we can do
        // Run the computation once again and make sure
        // it throws NoValueException again
        if (oldComputation == null) {
          assert(() {
            try {
              _f();
            } on NoValueException {
              // Good
              return true;
            } catch (_) {
              // Pass
            }
            return false;
          }(),
              "Computed expressions must be purely functional. Please use listeners for side effects.");
        }
        rethrow;
      } catch (e) {
        // Do not re-run f in this path to check for side effects
        // as thrown objects might not implement ==
        _lastResult = _ValueOrException.exc(e);
      } finally {
        final oldDiffNew = _lastUpstreamComputations.keys
            .toSet()
            .difference(_curUpstreamComputations!.keys.toSet());
        // Even for the non "resultful" case.
        // So that we can memoize that f threw NoValueException
        // when ran with a specific set of dependencies, for example.
        _lastUpstreamComputations = _curUpstreamComputations!;
        _curUpstreamComputations = null;
        for (var up in oldDiffNew) {
          up._removeDownstreamComputation(this);
        }
        // Bookkeep the fact the we ran/tried to run this computation
        // so that we can unlock its downstream during the DAG walk
        _lastUpdate = GlobalCtx._currentUpdate;
      }
      // The "resultful" case (the function either returned or threw an exception other than NoValueException)
      final shouldNotify =
          _prevResult?.shouldNotifyMemoized(_lastResult!) ?? true;
      for (var down in _nonMemoizedDownstreamComputations) {
        down._dirty = true;
      }
      if (shouldNotify) {
        _lastResultfulUpstreamComputations = _lastUpstreamComputations;
        for (var down in _memoizedDownstreamComputations) {
          down._dirty = true;
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

  void _removeDataSourcesAndUpstreams() {
    if (_lastUpstreamComputations.isNotEmpty || _dss != null) {
      _lastResult =
          null; // So that we re-run the next time we are subscribed to
      _lastResultfulUpstreamComputations = null;
    }
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

  T _use(bool memoized) {
    // Only routers can have non-memoized listeners
    assert(_dss != null || memoized);
    if (_computing) throw CyclicUseException();

    final caller = GlobalCtx.currentComputation;
    // Make sure the caller is subscribed
    caller._curUpstreamComputations![this] = _lastResult;
    // Only routers can have non-memoized downstream computations
    if (_dss != null) {
      // Make sure a downstream computation cannot be subscribed as both memoizing and non-memoizing
      if (memoized) {
        if (!this._nonMemoizedDownstreamComputations.contains(caller)) {
          this._memoizedDownstreamComputations.add(caller);
        }
      } else {
        this._memoizedDownstreamComputations.remove(caller);
        this._nonMemoizedDownstreamComputations.add(caller);
      }
    } else {
      this._memoizedDownstreamComputations.add(caller);
    }

    if ((GlobalCtx._currentUpdate == null ||
            _lastUpdate != GlobalCtx._currentUpdate) &&
        (_dss == null || _lastResult == null)) {
      // This means that this [use] happened outside the control of [_rerunGraph]
      // so be prudent and force a re-computation.
      // The main benefit is that this helps us detect cyclic dependencies.
      _evalF();
    }

    if (_lastResult == null) throw NoValueException();

    if (!memoized &&
        identityHashCode(_dss!._ds) !=
            identityHashCode(GlobalCtx._currentUpdateTriggerer)) {
      throw NoValueException();
    }

    return _lastResult!.value;
  }

  @override
  T get use {
    return _use(true);
  }
}
