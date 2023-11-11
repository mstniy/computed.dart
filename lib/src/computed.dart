import 'dart:async';

import '../computed.dart';

class NoValueException {}

class LastValue<T> {
  bool hasValue = false;
  T? lastValue;
}

class SubscriptionLastValue<T> extends LastValue<T> {
  StreamSubscription<T>? subscription;
}

class ComputedGlobalCtx {
  static final lvExpando = Expando<LastValue>('computed_lv');
}

class ComputedStreamResolverImpl implements ComputedStreamResolver {
  final ComputedImpl _parent;
  ComputedStreamResolverImpl(this._parent);
  T call<T>(Stream<T> s) {
    if (s is ComputedImpl<T>) {
      // Make sure we are subscribed
      _parent._upstreamComputations.putIfAbsent(
          s,
          () => s.listen((event) {
                _parent._maybeEvalF(true, null, null);
              })); // Handle onError (passthrough), onDone (close subscriptions to upstreams)
      if (!s._hasLastResult) s._evalF();
      return s._lastResult!; // What if f throws? _lastResult won't be set then
    } else {
      // Maintain a global cache of stream last values for any new dependencies discovered to use
      var lv = ComputedGlobalCtx.lvExpando[s];

      if (lv == null) {
        lv = LastValue();
        ComputedGlobalCtx.lvExpando[s] = lv;
      }
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
  final void Function(ComputedSubscription<T> sub) _removeSelfFromParent;
  void Function(T event)? _onData;
  Function? _onError;
  ComputedSubscription(this._removeSelfFromParent, this._onData, this._onError);
  @override
  Future<E> asFuture<E>([E? futureValue]) {
    throw UnimplementedError(); // Doesn't make much sense in this context
  }

  @override
  Future<void> cancel() async {
    _removeSelfFromParent(this);
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
  final _upstreamComputations = <ComputedImpl, StreamSubscription>{};
  final _dataSources = <Stream, SubscriptionLastValue>{};
  final _listeners = <ComputedSubscription<T>>{};
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
    } on NoValueException {
      // Not much we can do
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
    if (error == null) {
      for (var listener in _listeners)
        if (listener._onData != null) listener._onData!(t!);
    } else {
      // Exception
      for (var listener in _listeners)
        if (listener._onError != null) listener._onError!(error);
    }
  }

  void _maybeEvalF(bool noChangeComparison, dynamic old, dynamic neww) {
    if (_listeners.isEmpty) {
      _suppressedEvalDueToNoListener = true;
      return;
    }
    if (!noChangeComparison && old == neww) return;
    _evalF();
  }

  void _removeListener(ComputedSubscription<T> sub) {
    _listeners.remove(sub);
    if (_listeners.isEmpty) {
      // cancel subscriptions to all upstreams & remove them from the context (bonus: allow the user to specify a duration before doing that)
    }
  }

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final sub = ComputedSubscription<T>(_removeListener, onData, onError);
    if (_listeners.isEmpty && _suppressedEvalDueToNoListener) {
      _evalF();
      // Might set lastResult, won't notify the listener just yet (as that is against the Stream contract)
    }
    _listeners.add(sub);
    if (_hasLastResult && onData != null) {
      scheduleMicrotask(() {
        onData(_lastResult!);
      });
    }
    return sub;
  }
}
