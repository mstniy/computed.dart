import 'dart:async';

import 'package:meta/meta.dart';

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
    _validateOnError(handleError);
    _onError = handleError;
  }
}

void _validateOnError(Function? onError) {
  if (onError != null &&
      onError is! Function(Object, StackTrace) &&
      onError is! Function(Object)) {
    throw ArgumentError.value(onError, "onError",
        "onError must accept one Object or one Object and a StackTrace as arguments");
  }
}

void _dispatchOnError(Function onError, Object o, StackTrace st) {
  if (onError is Function(Object, StackTrace)) {
    onError(o, st);
  } else {
    onError(o);
  }
}

class _WeakMemoizedValueOrException<T> {
  final bool _weak;
  final bool _memoized;
  final _ValueOrException<T>? _voe;

  _WeakMemoizedValueOrException(this._weak, this._memoized, this._voe);
}

const _NoReactivityInsideReact =
    "`use`, `useWeak` and `react` not allowed inside react callbacks.";
const _NoReactivityOutsideComputations =
    "`use`, `useWeak`, `react` and `prev` are only allowed inside computations.";

class GlobalCtx {
  static ComputedImpl? _currentComputation;
  static ComputedImpl get currentComputation {
    if (_currentComputation == null) {
      throw StateError(_NoReactivityOutsideComputations);
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
            if (rvoe._voe!._isValue) return rvoe._voe!._value as T;
            Error.throwWithStackTrace(rvoe._voe!._exc!, rvoe._voe!._st!);
          }, true, false, false, null, null),
          currentValue != null
              ? _ValueOrException.value(currentValue())
              : null);
      // Run the subscriber outside the sync zone
      final zone = Zone.current[_isComputedZone] == true
          ? Zone.current.parent!
          : Zone.current;
      final sub = zone.run(() => dss(rvoe!._router));

      rvoe._router._dss ??= _DataSourceAndSubscription<T>(dataSource,
          currentValue != null ? GlobalCtx._currentUpdate : null, sub);
      GlobalCtx._routerExpando[dataSource] = rvoe;
      if (currentValue != null) rvoe._router.eval();
    }

    return rvoe;
  }

  // For each data source, have a "router", which is a computation that returns the
  // value, or throws the error, produced by the data source.
  // This allows most of the logic to only deal with upstream computations.
  static final _routerExpando = Expando<_RouterValueOrException>('computed');

  static var _currentUpdate = _Token(); // Guaranteed to be unique thanks to GC
  static Set<ComputedImpl> _currentUpdateNodes = {};
  static Expando<bool> _currentUpdateNodeDirty =
      Expando('computed_dag_runner_node_dirty');

  static var _reacting = false;
}

void _injectNodesToDAG(Set<Computed> nodes) {
  nodes.forEach((c) => GlobalCtx._currentUpdateNodeDirty[c] = true);
  GlobalCtx._currentUpdateNodes.addAll(nodes.cast<ComputedImpl>());
}

void _rerunGraph(Set<ComputedImpl> roots) {
  GlobalCtx._currentUpdateNodes = {};
  GlobalCtx._currentUpdateNodeDirty = Expando('computed_dag_runner_node_dirty');
  _injectNodesToDAG(roots);

  void _evalAfterEnsureUpstreamEvald(ComputedImpl node) {
    node._lastUpstreamComputations.keys.forEach((c) {
      if (c._lastUpdate != GlobalCtx._currentUpdate) {
        _evalAfterEnsureUpstreamEvald(c);
      }
    });
    // It is possible that this node has been forced to be evaluated by another
    // In this case, do not re-compute it again
    if (GlobalCtx._currentUpdateNodeDirty[node] == true) {
      try {
        final downstream = node.onDependencyUpdated();
        _injectNodesToDAG(downstream);
      } on NoValueException {
        // Pass. We must still consider the downstream.
      }
    }
  }

  while (GlobalCtx._currentUpdateNodes.isNotEmpty) {
    final cur = GlobalCtx._currentUpdateNodes.first;
    GlobalCtx._currentUpdateNodes.remove(cur);
    if (cur._lastUpdate == GlobalCtx._currentUpdate) continue;
    _evalAfterEnsureUpstreamEvald(cur);
  }
}

class ComputedImpl<T> implements Computed<T> {
  _DataSourceAndSubscription<T>? _dss;

  // Whether this node is memoized.
  // Always true for routers, which might have both memoized (.use)
  // and non-memoized (.react) listeners.
  final bool _memoized;
  final bool _assertIdempotent, _async;
  _Token? _lastUpdate;

  bool get _novalue => _lastResult == null;
  _ValueOrException<T>? _lastResult;
  _ValueOrException<T>? _prevResult;
  T? _initialPrev;
  var _lastUpstreamComputations =
      <ComputedImpl, _WeakMemoizedValueOrException>{};

  bool get _computing => _curUpstreamComputations != null;
  Object? _reactSuppressedException;
  StackTrace? _reactSuppressedExceptionStackTrace;
  Map<ComputedImpl, _WeakMemoizedValueOrException>? _curUpstreamComputations;

  final _memoizedDownstreamComputations = <ComputedImpl>{};
  final _nonMemoizedDownstreamComputations = <ComputedImpl>{};
  final _weakDownstreamComputations =
      <ComputedImpl>{}; // Note that these are always memoized

  // If mapped to false -> not notified yet
  final _listeners = <_ComputedSubscriptionImpl<T>, bool>{};

  final T Function() _f;

  final void Function()? _onCancel;
  final void Function(T value)? _dispose;

  void _use(bool weak) {
    if (_computing) throw CyclicUseException();

    final caller = GlobalCtx.currentComputation;
    if (GlobalCtx._reacting) {
      throw StateError(_NoReactivityInsideReact);
    }
    // Make sure the caller is subscribed, upgrade to non-weak if needed
    caller._curUpstreamComputations!.update(
        this,
        (v) =>
            _WeakMemoizedValueOrException(weak && v._weak, true, _lastResult),
        ifAbsent: () {
      // Check for cycles
      _checkCycle(caller);
      return _WeakMemoizedValueOrException(weak, true, _lastResult);
    });
  }

  @override
  T get use {
    _use(false);
    if (_lastUpdate != GlobalCtx._currentUpdate && _lastResult == null) {
      final downstream = eval();
      _injectNodesToDAG(downstream);
    }

    if (_lastResult == null) throw NoValueException();

    // We don't use Error.throwWithStackTrace here - even if we are a router
    // As this might make it more difficult to pinpoint where exceptions
    // are actually coming from.
    return _lastResult!.value;
  }

  @override
  T useOr(T value) {
    try {
      return use;
    } on NoValueException {
      return value;
    }
  }

  @override
  T get useWeak {
    _use(true);
    if (_lastResult == null) {
      if (_memoizedDownstreamComputations.isEmpty &&
          _nonMemoizedDownstreamComputations.isEmpty &&
          _listeners.isEmpty) {
        throw NoStrongUserException();
      } else
        throw NoValueException();
    }
    return _lastResult!.value;
  }

  @override
  T get prev {
    final caller = GlobalCtx.currentComputation;
    if (caller == this) {
      if (_prevResult == null && _initialPrev == null) throw NoValueException();
      return (_prevResult?.value ?? _initialPrev)!;
    } else {
      final mvoe = caller._lastUpstreamComputations[this];
      if (mvoe?._voe == null) {
        throw NoValueException();
      }
      return mvoe!._voe!.value;
    }
  }

  ComputedImpl(this._f, this._memoized, this._assertIdempotent, this._async,
      this._dispose, this._onCancel);

  static ComputedImpl<T> withPrev<T>(
      T Function(T prev) f,
      T initialPrev,
      bool memoized,
      bool assertIdempotent,
      bool async,
      void Function(T value)? dispose,
      void Function()? onCancel) {
    late ComputedImpl<T> c;
    c = ComputedImpl<T>(() => f(c._prevResult?.value ?? initialPrev), memoized,
        assertIdempotent && !async, async, dispose, onCancel);
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

    _rerunGraph({this});
  }

  void onDataSourceError(Object err, StackTrace st) {
    if (_dss == null) return;
    GlobalCtx._currentUpdate = _Token();

    _dss!._lastEmit = GlobalCtx._currentUpdate;
    final rvoe =
        GlobalCtx._routerExpando[_dss!._ds] as _RouterValueOrException<T>;
    if (rvoe._voe == null || rvoe._voe!._isValue || rvoe._voe!._exc != err) {
      // Update the global last value cache
      rvoe._voe = _ValueOrException<T>.exc(err, st);
    } else if (_nonMemoizedDownstreamComputations.isEmpty) {
      return;
    }

    _rerunGraph({this});
  }

  @override
  ComputedSubscription<T> listen(void Function(T event)? onData,
      [Function? onError]) {
    _validateOnError(onError);
    final sub = _ComputedSubscriptionImpl<T>(this, onData, onError);
    if (_novalue) {
      try {
        eval();
        // Might set lastResult, won't notify the listener just yet (as that is against the Stream contract)
      } on NoValueException {
        // It is fine if we don't have a value yet
      }
    }
    _listeners[sub] = false;

    if (!_novalue) {
      if (!_lastResult!._isValue &&
          onError == null &&
          _weakDownstreamComputations.isEmpty &&
          _memoizedDownstreamComputations.isEmpty &&
          _nonMemoizedDownstreamComputations.isEmpty &&
          _listeners.length == 1) {
        Zone.current.handleUncaughtError(_lastResult!._exc!, _lastResult!._st!);
      }
      scheduleMicrotask(() {
        if (_listeners[sub] != false)
          return; // We have been cancelled or the listener has already been notified
        // No need to set the value of _listeners here, it will never be used again
        if (!_novalue) {
          if (!_lastResult!._isValue) {
            if (sub._onError != null) {
              _dispatchOnError(
                  sub._onError!, _lastResult!._exc!, _lastResult!._st!);
            }
          } else if (_lastResult!._isValue && sub._onData != null) {
            final lastResult = _lastResult!._value as T;
            sub._onData!(lastResult);
          }
        }
      });
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
      Function? onError) {
    _validateOnError(onError);
    final rvoe =
        GlobalCtx._maybeCreateRouterFor<DT>(dataSource, dss, currentValue);

    // Routers don't call .react on data sources, they call .use
    assert(rvoe._router != this);

    rvoe._router._react(onData, onError);
  }

  // Returns the set of downstream nodes to be re-computed.
  // This is public so that it can be customized by subclasses
  Set<Computed> onDependencyUpdated() {
    return eval();
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
  // Can throw [NoValueException].
  // Returns the set of downstream nodes to be re-computed.
  // This is public so that it can be customized by subclasses
  @mustCallSuper
  Set<Computed> eval() {
    const idempotencyFailureMessage =
        "Computed expressions must be purely functional. Please use listeners for side effects. For computations creating asynchronous operations, make sure to use `Computed.async`.";
    GlobalCtx._currentUpdateNodeDirty[this] = null;
    final oldComputation = GlobalCtx._currentComputation;
    bool shouldNotify = false;
    try {
      _prevResult = _lastResult;
      _curUpstreamComputations = {};
      GlobalCtx._currentComputation = this;
      var newResult = _evalFGuarded();
      if (_assertIdempotent &&
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

      final gotNVE = !newResult._isValue && newResult._exc is NoValueException;

      shouldNotify = !gotNVE &&
          (!_memoized ||
              (_prevResult?.shouldNotifyMemoized(newResult) ?? true));

      if (shouldNotify) {
        _lastResult = newResult;
      }

      // Commit the changes to the DAG
      for (var e in _curUpstreamComputations!.entries) {
        final up = e.key;
        up._addDownstreamComputation(this, e.value._memoized, e.value._weak);
      }
      final oldDiffNew = _lastUpstreamComputations.keys
          .toSet()
          .difference(_curUpstreamComputations!.keys.toSet());
      for (var up in oldDiffNew) {
        up._removeDownstreamComputation(this);
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
        final downstream = <ComputedImpl>{};
        downstream.addAll(
            _nonMemoizedDownstreamComputations.where((c) => !c._computing));
        if (shouldNotify) {
          downstream.addAll(
              _memoizedDownstreamComputations.where((c) => !c._computing));
          // As a special case, if we are gaining our first strong user,
          // do not consider weak downstream "dirty".
          // The reasoning is that they likely have done an alternative,
          // lighter-weight computation already, which is still valid,
          // unless some other computation they depend on changes meaningfully.
          if (_lastUpdate != null) {
            downstream.addAll(
                _weakDownstreamComputations.where((c) => !c._computing));
          }
        }
        return downstream;
      }
    } finally {
      assert(_lastUpdate == GlobalCtx._currentUpdate);
      if (shouldNotify) {
        GlobalCtx._currentComputation = null;
        _notifyListeners();
      }
      GlobalCtx._currentComputation = oldComputation;
    }
  }

  void _notifyListeners() {
    // Take a copy in case the listeners cancel themselves/other listeners on this node
    final listenersCopy = _listeners.keys.toList();
    if (!_lastResult!._isValue) {
      // Exception
      var onErrorNotified = false;
      for (var listener in listenersCopy) {
        // Might have been cancelled, so double-check
        if (_listeners.containsKey(listener)) {
          _listeners[listener] = true;
          if (listener._onError != null) {
            onErrorNotified = true;
            _dispatchOnError(
                listener._onError!, _lastResult!._exc!, _lastResult!._st!);
          }
        }
      }
      if (_listeners
              .isNotEmpty && // As then we must have been called from an initial listen(), and it will handle this itself
          !onErrorNotified &&
          // Note that there is no need to check for lazy listeners here,
          // because even if we do have any, there must also be some non-lazy
          // downstream computation to trigger this.
          _memoizedDownstreamComputations.isEmpty &&
          _nonMemoizedDownstreamComputations.isEmpty) {
        // Propagate to the Zone
        Zone.current.handleUncaughtError(_lastResult!._exc!, _lastResult!._st!);
      }
    } else {
      for (var listener in listenersCopy) {
        // Might have been cancelled, so double-check
        if (_listeners.containsKey(listener)) {
          _listeners[listener] = true;
          if (listener._onData != null) {
            listener._onData!(_lastResult!._value as T);
          }
        }
      }
    }
  }

  void _addDownstreamComputation(ComputedImpl down, bool memoized, bool weak) {
    if (memoized) {
      if (_dss != null) {
        // Make sure a downstream computation cannot be subscribed as both memoizing and non-memoizing
        if (!_nonMemoizedDownstreamComputations.contains(down)) {
          (weak ? _weakDownstreamComputations : _memoizedDownstreamComputations)
              .add(down);
        }
      } else {
        // No need to check non-memoized computations here, only routers can have them
        (weak ? _weakDownstreamComputations : _memoizedDownstreamComputations)
            .add(down);
      }
    } else {
      assert(_dss !=
          null); // Only routers can have non-memoized downstream computations
      assert(!weak); // There is no weak .react
      // Make sure a downstream computation cannot be subscribed as both memoizing and non-memoizing
      // or weak and strong
      _weakDownstreamComputations.remove(down);
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

    if (_weakDownstreamComputations.isNotEmpty) {
      final weakDownstreamCopy =
          _weakDownstreamComputations.map((e) => (e, e._lastUpdate)).toSet();

      // Need to notify them, but not until the next microtask
      // As the caller of ComputedSubscription.cancel might not expect that
      scheduleMicrotask(() {
        final oldDownstreamFiltered = weakDownstreamCopy
            .where((c) =>
                // Filter out the computations which have been re-computed since
                // Note that this will also filter out the computations which have
                // since lost all their listeners, as we also set _lastUpdate = null
                // in that case.
                c.$1._lastUpdate == c.$2)
            .map((e) => e.$1)
            .toSet();
        GlobalCtx._currentUpdate = _Token();
        _rerunGraph(oldDownstreamFiltered);
      });
    }

    final lastResultBackup = _lastResult;

    _lastResult = null; // So that we re-run the next time we are subscribed to
    _lastUpdate = null;

    if (lastResultBackup != null) {
      if (lastResultBackup._isValue && _dispose != null) {
        _dispose(lastResultBackup._value as T);
      }
    }
    if (_onCancel != null) _onCancel();
  }

  void _removeDownstreamComputation(ComputedImpl c) {
    bool removed = _memoizedDownstreamComputations.remove(c) ||
        _nonMemoizedDownstreamComputations.remove(c) ||
        _weakDownstreamComputations.remove(c);
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

  void _react(void Function(T) onData, Function? onError) {
    // Only routers can be .react-ed to
    // As otherwise the meaning of .prev becomes ambiguous
    assert(_dss != null);
    final caller = GlobalCtx.currentComputation;
    if (GlobalCtx._reacting) {
      throw StateError(_NoReactivityInsideReact);
    }
    // Make sure the caller is subscribed
    caller._curUpstreamComputations![this] =
        _WeakMemoizedValueOrException(false, false, _lastResult);

    if (_dss!._lastEmit != GlobalCtx._currentUpdate) {
      // Don't call the functions
      return;
    }

    GlobalCtx._reacting = true;
    try {
      if (_lastResult!._isValue) {
        onData(_lastResult!._value as T);
      } else if (onError != null) {
        _dispatchOnError(onError, _lastResult!._exc!, _lastResult!._st!);
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
}
