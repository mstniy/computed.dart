import 'dart:async';
import 'package:meta/meta.dart';

import '../computed.dart';
import 'data_source_subscription.dart';

class _UpdateToken {
  _UpdateToken();
}

class _ValueOrException<T> {
  bool _isValue;
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

  bool shouldNotify(_ValueOrException<T> other) {
    // Do not memoize exceptions
    return !_isValue || (!other._isValue) || (_value != other._value);
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

class GlobalCtx {
  static ComputedImpl? _currentComputation;
  static ComputedImpl get currentComputation {
    if (_currentComputation == null) {
      throw StateError(
          "`use` and `prev` are only allowed inside Computed expressions.");
    }
    return _currentComputation!;
  }

  // For each data source, have a "router", which is a computation that returns the
  // value, or throws the error, produced by the data source.
  // This allows most of the logic to only deal with upstream computations.
  @visibleForTesting
  static final routerExpando = Expando<_RouterValueOrException>('computed');

  static _UpdateToken? _currentUpdate;
}

class ComputedListenerSubscription<T> {
  ComputedImpl<T> _node;
  void Function(T event)? _onData;
  Function? _onError;

  ComputedListenerSubscription(this._node, this._onData, this._onError);

  Future<void> cancel() async {
    _node._removeListener(this);
  }

  void onData(void Function(T data)? handleData) {
    _onData = handleData;
  }

  void onError(Function? handleError) {
    _onError = handleError;
  }
}

class ComputedImpl<T> with Computed<T> {
  Map<ComputedImpl, _ValueOrException?>? _lastResultfulUpstreamComputations;
  var _lastUpstreamComputations = <ComputedImpl, _ValueOrException?>{};
  Map<ComputedImpl, _ValueOrException?>? _curUpstreamComputations;
  final _downstreamComputations = <ComputedImpl>{};

  _DataSourceAndSubscription<T>? _dss;
  final _listeners = Set<ComputedListenerSubscription<T>>();

  bool get _novalue => _lastResult == null;
  _UpdateToken? _lastUpdate;
  bool get _computing => _curUpstreamComputations != null;

  _ValueOrException<T>? _lastResult;
  _ValueOrException<T>? _prevResult;

  @override
  T get prev {
    final caller = GlobalCtx.currentComputation;
    if (caller._novalue)
      throw NoValueException(); // Even if we are on the caller's memoization table
    if (caller == this) {
      if (_prevResult == null) throw NoValueException();
      return _prevResult!.value;
    } else {
      if (caller._lastResult == null) throw NoValueException();
      final voe = caller._lastResultfulUpstreamComputations![this];
      if (voe == null) throw NoValueException();
      return voe.value;
    }
  }

  T Function() _f;
  final T Function() _origF;

  ComputedImpl(this._f) : _origF = _f;

  void _onDataSourceData(T data) {
    if (_dss == null) return;
    final rvoe =
        GlobalCtx.routerExpando[_dss!._ds] as _RouterValueOrException<T>;
    // TODO: Consider exceptions
    if (rvoe._voe != null && rvoe._voe!._value == data) return;
    // Update the global last value cache
    rvoe._voe = _ValueOrException<T>.value(data);

    _rerunGraph();
  }

  ComputedListenerSubscription<T> listen(
      void Function(T event)? onData, Function? onError) {
    final sub = ComputedListenerSubscription<T>(this, onData, onError);
    if (_novalue) {
      try {
        _evalF();
        // Might set lastResult, won't notify the listener just yet (as that is against the Stream contract)
      } on NoValueException {}
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

  DT useDataSource<DT>(
      Object dataSource,
      DT Function() dataSourceUse,
      DataSourceSubscription<DT> Function(void Function(DT data) onData) dss,
      bool hasCurrentValue,
      DT? currentValue) {
    var rvoe =
        GlobalCtx.routerExpando[dataSource] as _RouterValueOrException<DT>?;

    if (rvoe == null) {
      rvoe = _RouterValueOrException(ComputedImpl(dataSourceUse),
          hasCurrentValue ? _ValueOrException.value(currentValue!) : null);
      GlobalCtx.routerExpando[dataSource] = rvoe;
    }

    if (rvoe._router != this) {
      // Subscribe to the router instead
      return rvoe._router.use;
    }
    // We are the router (thus, DT == T)
    // Make sure we are subscribed
    if (_dss == null) {
      _dss = _DataSourceAndSubscription<T>(
          dataSource,
          dss((data) => _onDataSourceData(data as T))
              as DataSourceSubscription<T>);
    }

    if (rvoe._voe == null) {
      throw NoValueException();
    }
    return rvoe._voe!.value;
  }

  DT dataSourcePrev<DT>(Object dataSource) {
    if (_novalue)
      throw NoValueException(); // Even if the data source is in our memoization table
    final rvoe =
        GlobalCtx.routerExpando[dataSource] as _RouterValueOrException<DT>?;
    if (rvoe == null) throw NoValueException();
    final memoizedVOE = _lastResultfulUpstreamComputations![rvoe._router];
    if (memoizedVOE == null) throw NoValueException();
    return memoizedVOE.value;
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
    try {
      final numUnsatDep = <ComputedImpl, int>{};
      final noUnsatDep = <ComputedImpl>{this};
      final done = <ComputedImpl>{};

      while (noUnsatDep.isNotEmpty) {
        final cur = noUnsatDep.first;
        noUnsatDep.remove(cur);
        if (done.contains(cur)) continue;
        try {
          if (cur._downstreamComputations.isEmpty && cur._listeners.isEmpty) {
            continue;
          }
          if (cur._lastUpdate != GlobalCtx._currentUpdate) {
            try {
              if (cur == this)
                _evalF();
              else
                cur._maybeEvalF();
            } on NoValueException {
              // Do not evaluate the children
              continue;
            }
          }
          for (var down in cur._downstreamComputations) {
            if (!done.contains(down)) {
              var nud = numUnsatDep[down];
              if (nud == null) {
                nud = 0;
                for (var up in down._lastUpstreamComputations.keys) {
                  nud =
                      nud! + ((up._dss == null) ? 1 : ((up._novalue) ? 1 : 0));
                }
              }
              if (cur._dss == null) nud = nud! - 1;
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
    }
  }

  void _maybeEvalF() {
    if (_lastResult == null || _dss != null) {
      _evalF();
      return;
    }
    for (var compVOE in _lastUpstreamComputations.entries) {
      final comp = compVOE.key;
      if (comp._lastResult == null) continue;
      final voe = compVOE.value;
      if (voe == null ||
          !voe._isValue ||
          !comp._lastResult!._isValue ||
          voe._value != comp._lastResult!._value) {
        _evalF();
        return;
      }
    }
  }

  // Also notifies the listeners (but not downstream computations) if necessary
  void _evalF() {
    final oldComputation = GlobalCtx._currentComputation;
    try {
      final oldPrevResult = _prevResult;
      final oldUpstreamComputations = _lastUpstreamComputations;
      _prevResult = _lastResult;
      // Never memoize exceptions
      _curUpstreamComputations = {};
      try {
        GlobalCtx._currentComputation = this;
        final newResult = _ValueOrException.value(_f());
        assert(_f() == newResult._value,
            "Computed expressions must be purely functional. Please use listeners for side effects.");
        _lastResult = newResult;
      } on NoValueException {
        // Not much we can do
        rethrow;
      } catch (e) {
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
      }
      // The "resultful" case (the function either returned or threw an exception (not an Error) other than NoValueException)
      _lastUpdate = GlobalCtx._currentUpdate;
      final shouldNotify = _prevResult?.shouldNotify(_lastResult!) ?? true;
      if (shouldNotify) {
        _lastResultfulUpstreamComputations = _lastUpstreamComputations;
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
      for (var listener in _listeners)
        if (listener._onError != null) listener._onError!(_lastResult!._exc!);
    } else {
      for (var listener in _listeners)
        if (listener._onData != null)
          listener._onData!(_lastResult!._value as T);
    }
  }

  void _removeDataSourcesAndUpstreams() {
    if (_lastUpstreamComputations.isNotEmpty || _dss != null) {
      _lastResult =
          null; // So that we re-run the next time we are subscribed to
      _lastResultfulUpstreamComputations = null;
    }
    for (var upComp in _lastUpstreamComputations.keys)
      upComp._removeDownstreamComputation(this);
    _lastUpstreamComputations = {};
    if (_dss != null) {
      _dss!._dss.cancel();
      // Remove ourselves from the expando
      GlobalCtx.routerExpando[_dss!._ds] = null;
      _dss = null;
    }
  }

  void _removeDownstreamComputation(ComputedImpl c) {
    assert(_downstreamComputations.remove(c));
    if (_downstreamComputations.isEmpty && _listeners.isEmpty) {
      _removeDataSourcesAndUpstreams();
    }
  }

  void _removeListener(ComputedListenerSubscription<T> sub) {
    _listeners.remove(sub);
    if (_downstreamComputations.isEmpty && _listeners.isEmpty) {
      _removeDataSourcesAndUpstreams();
    }
  }

  @override
  T get use {
    final caller = GlobalCtx.currentComputation;
    // Make sure the caller is subscribed
    caller._curUpstreamComputations![this] = _lastResult;
    this._downstreamComputations.add(caller);

    if (_computing) throw CyclicUseException();

    if (GlobalCtx._currentUpdate == null ||
        _lastUpdate != GlobalCtx._currentUpdate) {
      // This means that this [use] happened outside the control of [_rerunGraph]
      // so be prudent and force a re-computation.
      // The main benefit is that this helps us detect cyclic dependencies.
      _evalF();
    }

    if (_lastResult == null) throw NoValueException();
    return _lastResult!.value;
  }
}
