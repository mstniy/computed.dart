import 'dart:async';

import 'package:built_collection/built_collection.dart';

class NoValueException {}

class SubscriptionLastValue<T> {
  StreamSubscription<T>? subscription;
  bool hasValue = false;
  T? lastValue;
}

class ComputedGlobalCtx {
  static final slvExpando =
      Expando<SubscriptionLastValue>('computed_slv_expando');
}

class ComputedStreamResolver {
  final Computed _parent;
  ComputedStreamResolver(this._parent);
  T call<T>(Stream<T> s) {
    if (s is Computed<T>) {
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
      // TODO: When to unsubscribe?
      var slv = ComputedGlobalCtx.slvExpando[s];

      if (slv == null) {
        slv = SubscriptionLastValue();
        slv.subscription = s.listen((value) {
          slv!.hasValue = true;
          slv.lastValue = value;
        });
        ComputedGlobalCtx.slvExpando[s] = slv;
      }
      // Make sure we are subscribed
      _parent._dataSources.putIfAbsent(s, () {
        final slv = SubscriptionLastValue();
        slv.subscription = s.listen((event) {
          final oldHasValue = slv.hasValue;
          final oldLastValue = slv.lastValue;
          slv.hasValue = true;
          slv.lastValue = event;
          _parent._maybeEvalF(!oldHasValue, oldLastValue, event);
        });
        return slv;
      }); // Handle onError (passthrough), onDone (close subscriptions to upstreams)
      if (!slv.hasValue) {
        throw NoValueException();
      }
      return slv.lastValue!;
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

class Computed<T> extends Stream<T> {
  final _upstreamComputations = <Computed, StreamSubscription>{};
  final _dataSources = <Stream, SubscriptionLastValue>{};
  final _listeners = <ComputedSubscription<T>>{};
  var _suppressedEvalDueToNoListener = true;
  var _hasLastResult = false;
  bool get hasLastResult => _hasLastResult;
  T? _lastResult;
  T? get lastResult => _lastResult;
  final T Function(ComputedStreamResolver ctx) f;

  Computed(this.f);

  void _evalF() {
    _suppressedEvalDueToNoListener = false;
    late T fRes;
    var fFinished = false;
    try {
      fRes = f(ComputedStreamResolver(this));
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

void main() async {
  final controller = StreamController<BuiltList<int>>(
      sync: true); // Use a sync controller to make debugging easier
  final source = controller.stream.asBroadcastStream();

  final anyNegative =
      Computed((ctx) => ctx(source).any((element) => element < 0));

  final maybeReversed = Computed((ctx) =>
      ctx(anyNegative) ? ctx(source).reversed.toBuiltList() : ctx(source));

  final append0 = Computed((ctx) {
    return ctx(maybeReversed).rebuild((p0) => p0.add(0));
  });

  append0.listen((value) => print(value));

  final unused = Computed((ctx) {
    while (true) {
      print("Never prints, this computation is never used.");
    }
  });

  controller.add([1, 2, -3, 4].toBuiltList()); // prints [4, -3, 2, 1, 0]
  controller.add([1, 2, -3, -4].toBuiltList()); // prints [-4, -3, 2, 1, 0]
  controller.add([4, 5, 6].toBuiltList()); // prints [4, 5, 6, 0]
  controller.add([4, 5, 6].toBuiltList()); // Same result: Not printed again
}
