import 'dart:async';

import 'package:meta/meta.dart';

import '../computed.dart';
import 'data_source_subscription.dart';
import 'sync_zone.dart';
import 'utils/value_or_exception.dart';

class _Token {
  _Token();
}

final _isComputedZone = _Token();

class _RouterValueOrException<T> {
  final RouterImpl<T> _router;
  ValueOrException<T>? _voe;

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

void _dispatchOnError(Function onError, Object o, StackTrace? st) {
  if (onError is Function(Object, StackTrace)) {
    onError(o, st ?? StackTrace.empty);
  } else {
    onError(o);
  }
}

class _WeakMemoizedValueOrException<T> {
  final bool _weak;
  final bool _memoized;
  final ValueOrException<T>? _voe;

  _WeakMemoizedValueOrException(this._weak, this._memoized, this._voe);
}

const _noReactivityInsideReact =
    "`use`, `useWeak` and `react` not allowed inside react callbacks.";
const _noReactivityOutsideComputations =
    "`use`, `useWeak`, `react` and `prev` are only allowed inside computations.";

class GlobalCtx {
  static ComputedImpl? _currentComputation;
  static ComputedImpl get currentComputation {
    if (_currentComputation == null) {
      throw StateError(_noReactivityOutsideComputations);
    }
    return _currentComputation!;
  }

  @visibleForTesting
  static RouterImpl? routerFor(Object ds) {
    return _routerExpando[ds]?._router;
  }

  static _RouterValueOrException<T> _maybeCreateRouterFor<T>(
      Object dataSource,
      DataSourceSubscription<T> Function(RouterImpl<T> router) dss,
      T Function()? currentValue) {
    var rvoe =
        GlobalCtx._routerExpando[dataSource] as _RouterValueOrException<T>?;

    if (rvoe == null) {
      rvoe = _RouterValueOrException(RouterImpl._(() => rvoe!._voe),
          currentValue != null ? ValueOrException.value(currentValue()) : null);
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
  static Expando<bool> _currentUpdateNodeDirty = Expando();
  static Expando<Map<ComputedImpl, _WeakMemoizedValueOrException>>
      _currentUpdateUpstreamComputations = Expando();

  static var _reacting = false;
}

void _injectNodesToDAG(Set<Computed> nodes) {
  for (var c in nodes) {
    GlobalCtx._currentUpdateNodeDirty[c] = true;
  }
  GlobalCtx._currentUpdateNodes.addAll(nodes.cast<ComputedImpl>());
}

void _rerunGraph(Set<ComputedImpl> roots) {
  GlobalCtx._currentUpdateNodes = {};
  GlobalCtx._currentUpdateNodeDirty = Expando();
  GlobalCtx._currentUpdateUpstreamComputations = Expando();
  _injectNodesToDAG(roots);

  void evalAfterEnsureUpstreamEvald(ComputedImpl node) {
    for (var c in node._lastUpstreamComputations.keys) {
      if (c._lastUpdate != GlobalCtx._currentUpdate) {
        evalAfterEnsureUpstreamEvald(c);
      }
    }
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
    evalAfterEnsureUpstreamEvald(cur);
  }
}

class ComputedImpl<T> implements Computed<T> {
  final bool _assertIdempotent, _async;
  _Token? _lastUpdate;

  bool get _novalue => _lastResult == null;
  ValueOrException<T>? _lastResult;
  ValueOrException<T>? _prevResult;
  T? _initialPrev;
  var _lastUpstreamComputations =
      <ComputedImpl, _WeakMemoizedValueOrException>{};

  bool get _computing =>
      GlobalCtx._currentUpdateUpstreamComputations[this] != null;

  final _memoizedDownstreamComputations = <ComputedImpl>{};
  final _weakDownstreamComputations =
      <ComputedImpl>{}; // Note that these are always memoized

  // If mapped to false -> not notified yet
  final _listeners = <_ComputedSubscriptionImpl<T>, bool>{};

  final T Function() _f;

  final void Function()? _onCancel;
  final void Function(T value)? _dispose;

  bool _hasStrongUsers() =>
      _memoizedDownstreamComputations.isNotEmpty || _listeners.isNotEmpty;

  bool _hasStrongDownstreamComputations() =>
      _memoizedDownstreamComputations.isNotEmpty;

  bool _hasDownstreamComputations() =>
      _memoizedDownstreamComputations.isNotEmpty ||
      _weakDownstreamComputations.isNotEmpty;

  void _use(bool weak) {
    if (_computing) throw CyclicUseException();

    final caller = GlobalCtx.currentComputation;
    if (GlobalCtx._reacting) {
      throw StateError(_noReactivityInsideReact);
    }
    // Make sure the caller is subscribed, upgrade to non-weak if needed
    GlobalCtx._currentUpdateUpstreamComputations[caller]!.update(
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

    switch (_lastResult) {
      case null:
        throw NoValueException();
      // We don't use Error.throwWithStackTrace here - even if we are a router
      // As this might make it more difficult to pinpoint where exceptions
      // are actually coming from.
      case ValueOrException<T>(valueOrThrow: final v):
        return v;
    }
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
      if (!_hasStrongUsers()) {
        throw NoStrongUserException();
      } else {
        throw NoValueException();
      }
    }
    return _lastResult!.valueOrThrow;
  }

  @override
  T get prev {
    final caller = GlobalCtx.currentComputation;
    if (caller == this) {
      if (_prevResult == null && _initialPrev == null) throw NoValueException();
      return (_prevResult?.valueOrThrow ?? _initialPrev)!;
    } else {
      final mvoe = caller._lastUpstreamComputations[this];
      if (mvoe?._voe == null) {
        throw NoValueException();
      }
      return mvoe!._voe!.valueOrThrow;
    }
  }

  ComputedImpl(this._f, this._assertIdempotent, this._async, this._dispose,
      this._onCancel);

  static ComputedImpl<T> withPrev<T>(
      T Function(T prev) f,
      T initialPrev,
      bool assertIdempotent,
      bool async,
      void Function(T value)? dispose,
      void Function()? onCancel) {
    late ComputedImpl<T> c;
    c = ComputedImpl<T>(() => f(c._prevResult?.valueOrThrow ?? initialPrev),
        assertIdempotent && !async, async, dispose, onCancel);
    c._initialPrev = initialPrev;

    return c;
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
      switch (_lastResult!) {
        case Exception(exc: final exc, st: final st):
          if (onError == null &&
              !_hasDownstreamComputations() &&
              _listeners.length == 1) {
            Zone.current.handleUncaughtError(exc, st ?? StackTrace.empty);
          }
        case Value():
        // pass
      }

      scheduleMicrotask(() {
        if (_listeners[sub] != false) {
          return; // We have been cancelled or the listener has already been notified
        }
        // No need to set the value of _listeners here, it will never be used again
        // Note that _lastResult cannot be null here - for that we must have been cancelled,
        //  but we just checked that we are not.
        switch (_lastResult!) {
          case Value<T>(value: final value):
            if (sub._onData != null) {
              sub._onData!(value);
            }
          case Exception<T>(exc: final exc, st: final st):
            if (sub._onError != null) {
              _dispatchOnError(sub._onError!, exc, st);
            }
        }
      });
    }
    return sub;
  }

  DT dataSourceUse<DT>(
      Object dataSource,
      DataSourceSubscription<DT> Function(RouterImpl<DT> router) dss,
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
      DataSourceSubscription<DT> Function(RouterImpl<DT> router) dss,
      DT Function()? currentValue,
      void Function(DT) onData,
      Function? onError) {
    _validateOnError(onError);
    final rvoe =
        GlobalCtx._maybeCreateRouterFor<DT>(dataSource, dss, currentValue);

    // Routers don't call .react on data sources, they call .use
    // ignore: unrelated_type_equality_checks
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

  ValueOrException<T> _evalFGuarded() {
    try {
      return ValueOrException.value(_evalFInZone());
    } catch (e, s) {
      return ValueOrException.exc(e, s);
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
      GlobalCtx._currentUpdateUpstreamComputations[this] = {};
      GlobalCtx._currentComputation = this;
      var newResult = _evalFGuarded();
      if (_assertIdempotent &&
          switch (newResult) {
            Value() => true,
            Exception(exc: final exc) => exc is NoValueException
          }) {
        // Run f() once again and see if it behaves identically
        bool ensureIdempotent() {
          final idempotentResult = _evalFGuarded();
          return newResult.equals(idempotentResult);
        }

        try {
          assert(ensureIdempotent(), idempotencyFailureMessage);
        } on AssertionError catch (e, s) {
          newResult = ValueOrException.exc(e, s);
        }
      }

      final gotNVE = switch (newResult) {
        Value<T>() => false,
        Exception<T>(exc: final exc) => exc is NoValueException,
      };

      final prevEqualsNew = _prevResult?.equals(newResult) ?? false;

      if (!prevEqualsNew && _prevResult is Value<T> && _dispose != null) {
        _dispose((_prevResult as Value<T>).value);
      }

      // Do not notify downstream for transitions to NVE
      shouldNotify = !prevEqualsNew && !gotNVE;

      if (shouldNotify) {
        _lastResult = newResult;
      }

      // Commit the changes to the DAG
      for (var e
          in GlobalCtx._currentUpdateUpstreamComputations[this]!.entries) {
        final up = e.key;
        up._addDownstreamComputation(this, e.value._memoized, e.value._weak);
      }
      final oldDiffNew = _lastUpstreamComputations.keys.toSet().difference(
          GlobalCtx._currentUpdateUpstreamComputations[this]!.keys.toSet());
      for (var up in oldDiffNew) {
        up._removeDownstreamComputation(this);
      }

      // Even if f() throws NoValueException
      // So that we can memoize that f threw NoValueException
      // when ran with a specific set of dependencies, for example.
      _lastUpstreamComputations =
          GlobalCtx._currentUpdateUpstreamComputations[this]!;
      GlobalCtx._currentUpdateUpstreamComputations[this] = null;
      // Bookkeep the fact the we ran/tried to run this computation
      // so that we can unlock its downstream during the DAG walk
      _lastUpdate = GlobalCtx._currentUpdate;

      if (gotNVE) {
        final Exception(:exc, :st) = newResult as Exception;
        Error.throwWithStackTrace(exc, st ?? StackTrace.empty);
      } else {
        final downstream = <ComputedImpl>{};
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
    switch (_lastResult!) {
      case Value<T>(value: final value):
        for (var listener in listenersCopy) {
          // Might have been cancelled, so double-check
          if (_listeners.containsKey(listener)) {
            _listeners[listener] = true;
            if (listener._onData != null) {
              listener._onData!(value);
            }
          }
        }
      case Exception<T>(exc: final exc, st: final st):
        var onErrorNotified = false;
        for (var listener in listenersCopy) {
          // Might have been cancelled, so double-check
          if (_listeners.containsKey(listener)) {
            _listeners[listener] = true;
            if (listener._onError != null) {
              onErrorNotified = true;
              _dispatchOnError(listener._onError!, exc, st);
            }
          }
        }
        if (_listeners
                .isNotEmpty && // As then we must have been called from an initial listen(), and it will handle this itself
            !onErrorNotified &&
            // Note that there is no need to check for lazy listeners here,
            // because even if we do have any, there must also be some non-lazy
            // downstream computation to trigger this.
            !_hasStrongDownstreamComputations()) {
          // Propagate to the Zone
          Zone.current.handleUncaughtError(exc, st ?? StackTrace.empty);
        }
    }
  }

  void _addDownstreamComputation(ComputedImpl down, bool memoized, bool weak) {
    // Only routers can have non-memoized downstream computations
    assert(memoized);
    (weak ? _weakDownstreamComputations : _memoizedDownstreamComputations)
        .add(down);
  }

  void _removeDataSourcesAndUpstreams() {
    for (var upComp in _lastUpstreamComputations.keys) {
      upComp._removeDownstreamComputation(this);
    }
    _lastUpstreamComputations = {};

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

    switch (lastResultBackup) {
      case Value<T>(value: final value):
        if (_dispose != null) {
          _dispose(value);
        }
      case _:
      // pass
    }

    if (_onCancel != null) _onCancel();
  }

  void _removeDownstreamComputation(ComputedImpl c) {
    bool wasWeak = _weakDownstreamComputations.contains(c);
    bool removed = _memoizedDownstreamComputations.remove(c) ||
        _weakDownstreamComputations.remove(c);
    assert(removed, "Corrupted internal state");
    if (!wasWeak && !_hasStrongUsers()) {
      _removeDataSourcesAndUpstreams();
    }
  }

  void _removeListener(ComputedSubscription<T> sub) {
    if (_listeners.remove(sub) == null) {
      return;
    }
    if (!_hasStrongUsers()) {
      _removeDataSourcesAndUpstreams();
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

final class RouterImpl<T> extends ComputedImpl<T> {
  _DataSourceAndSubscription<T>? _dss;
  final _nonMemoizedDownstreamComputations = <ComputedImpl>{};

  RouterImpl._(ValueOrException<T>? Function() voe)
      : super(() {
          switch (voe()) {
            case null:
              throw NoValueException();
            case Value<T>(value: final value):
              return value;
            case Exception<T>(exc: final exc, st: final st):
              Error.throwWithStackTrace(exc, st ?? StackTrace.empty);
          }
        }, false, false, null, null);

  @override
  bool _hasStrongUsers() =>
      super._hasStrongUsers() || _nonMemoizedDownstreamComputations.isNotEmpty;

  @override
  bool _hasStrongDownstreamComputations() =>
      super._hasStrongDownstreamComputations() ||
      _nonMemoizedDownstreamComputations.isNotEmpty;

  @override
  bool _hasDownstreamComputations() =>
      super._hasDownstreamComputations() ||
      _nonMemoizedDownstreamComputations.isNotEmpty;

  void onDataSourceData(T data) {
    if (_dss == null) return;
    GlobalCtx._currentUpdate = _Token();
    _dss!._lastEmit = GlobalCtx._currentUpdate;
    final rvoe =
        GlobalCtx._routerExpando[_dss!._ds] as _RouterValueOrException<T>;
    if (switch (rvoe._voe) {
      Value<T>(value: final value) => value != data,
      _ => true
    }) {
      // Update the global last value cache
      rvoe._voe = ValueOrException<T>.value(data);
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
    if (switch (rvoe._voe) {
      Exception(exc: final exc) => exc != err,
      _ => true
    }) {
      // Update the global last value cache
      rvoe._voe = ValueOrException<T>.exc(err, st);
    } else if (_nonMemoizedDownstreamComputations.isEmpty) {
      return;
    }

    _rerunGraph({this});
  }

  void _react(void Function(T) onData, Function? onError) {
    // Only routers can be .react-ed to
    assert(_dss != null);
    final caller = GlobalCtx.currentComputation;
    if (GlobalCtx._reacting) {
      throw StateError(_noReactivityInsideReact);
    }
    // Make sure the caller is subscribed
    GlobalCtx._currentUpdateUpstreamComputations[caller]![this] =
        _WeakMemoizedValueOrException(false, false, _lastResult);

    if (_dss!._lastEmit != GlobalCtx._currentUpdate) {
      // Don't call the functions
      return;
    }

    GlobalCtx._reacting = true;
    try {
      switch (_lastResult!) {
        case Value<T>(value: final value):
          onData(value);
        case Exception<T>(exc: final exc, st: final st):
          if (onError != null) {
            _dispatchOnError(onError, exc, st);
          } else {
            // We don't use Error.throwWithStackTrace here
            // As this might make it more difficult to pinpoint where exceptions
            // are actually coming from.
            throw exc;
          }
      }
    } finally {
      GlobalCtx._reacting = false;
    }
  }

  @override
  void _addDownstreamComputation(ComputedImpl down, bool memoized, bool weak) {
    if (memoized) {
      // Make sure a downstream computation cannot be subscribed as both memoizing and non-memoizing
      if (!_nonMemoizedDownstreamComputations.contains(down)) {
        (weak ? _weakDownstreamComputations : _memoizedDownstreamComputations)
            .add(down);
      }
    } else {
      assert(!weak); // There is no weak .react
      // Make sure a downstream computation cannot be subscribed as both memoizing and non-memoizing
      // or weak and strong
      _weakDownstreamComputations.remove(down);
      _memoizedDownstreamComputations.remove(down);
      _nonMemoizedDownstreamComputations.add(down);
    }
  }

  @override
  void _removeDataSourcesAndUpstreams() {
    _dss!._dss.cancel();
    // Remove ourselves from the expando
    GlobalCtx._routerExpando[_dss!._ds] = null;
    _dss = null;
    super._removeDataSourcesAndUpstreams();
  }

  @override
  void _removeDownstreamComputation(ComputedImpl c) {
    if (_nonMemoizedDownstreamComputations.remove(c)) {
      if (!_hasStrongUsers()) {
        _removeDataSourcesAndUpstreams();
      }
    } else {
      super._removeDownstreamComputation(c);
    }
  }

  @override
  Set<Computed> eval() {
    final superRes = super.eval();
    // Always notify the non-memoized downstream
    superRes
        .addAll(_nonMemoizedDownstreamComputations.where((c) => !c._computing));

    return superRes;
  }
}
