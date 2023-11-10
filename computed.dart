import 'dart:async';

class NoValueException {}

class NoSubscriptionException<T> {
  Stream<T> s;
  NoSubscriptionException(this.s);
}

class SubscriptionLastValueRefCtr<T> {
  StreamSubscription<T> subscription;
  bool hasValue = false;
  T? lastValue;
  int refCtr = 1;
  SubscriptionLastValueRefCtr(this.subscription);
}

class ComputedGlobalCtx {
  static final streams = <Stream, SubscriptionLastValueRefCtr>{};
}

class ComputedStreamResolver {
  final Computed _parent;
  ComputedStreamResolver(this._parent);
  T call<T>(Stream<T> s) {
    late SubscriptionLastValueRefCtr? slv;
    if (s is Computed<T>) {
      // Make sure we are subscribed
      _parent._upstreamComputations.putIfAbsent(
          s,
          () => s.listen((event) {
                // Store the last value of upstream comps, do not reeval if it didn't change
                _parent._maybeEvalF();
              }) as ComputedSubscription);
      if (!s._hasLastResult)
        s._evalF(); // What if f throws? _lastResult won't be set then
      return s._lastResult!;
    } else {
      // Refer to the global map
      slv = ComputedGlobalCtx.streams[s];
      if (slv == null) throw NoSubscriptionException(s);
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
  // We store these here instead of the global dict to avoid the global dict becoming too large
  // Reasoning: A real-world application might have lots of computations but likely much fewer actual streams
  final _upstreamComputations = <Computed, ComputedSubscription>{};
  final _listeners = <ComputedSubscription<T>>{};
  var _hasLastResult = false;
  bool get hasLastResult => _hasLastResult;
  T? _lastResult;
  T? get lastResult => _lastResult;
  final T Function(ComputedStreamResolver ctx) f;
  Computed(this.f) {
    _evalF();
  }

  void _evalF() {
    late T fRes;
    var fFinished = false;
    try {
      fRes = f(ComputedStreamResolver(this));
      // cancel subscriptions to unused streams & remove them from the context (bonus: allow the user to specify a duration before doing that)
      fFinished = true;
    } on NoValueException {
      // Not much we can do
    } on NoSubscriptionException catch (e) {
      late SubscriptionLastValueRefCtr slv;
      slv = SubscriptionLastValueRefCtr(e.s.listen((event) {
        slv.hasValue = true;
        slv.lastValue = event;
        _maybeEvalF();
      })); // Handle onError (passthrough), onDone (close subscriptions to upstreams)
      assert(e.s
          is! Computed); // We never raise SubscriptionException-s on Computed-s
      ComputedGlobalCtx.streams[e.s] = slv;
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

  void _maybeEvalF() {
    if (_listeners.isNotEmpty) _evalF();
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
    _listeners.add(sub);
    // if this is the only listener: try running f(), if it succeeds, notify the listener right away
    // if this is not the only listener, and we have firstData, notify the listener right away
    return sub;
  }
}

void main() async {
  final controller = StreamController<List<int>>();
  final source = controller.stream.asBroadcastStream();

  final anyNegative =
      Computed((ctx) => ctx(source).any((element) => element < 0));

  final maybeReversed = Computed(
      (ctx) => ctx(anyNegative) ? ctx(source).reversed.toList() : ctx(source));

  final append0 = Computed((ctx) => List<int>.of(ctx(maybeReversed))..add(0));

  append0.listen((value) => print(value));

  final unused = Computed((ctx) {
    ctx(source);
    print("Never prints, this computation is never used.");
  });

  controller.add([1, 2, -3]); // prints [-3, 2, 1, 0]
  controller.add([4, 5, 6]); // prints [4, 5, 6, 0]
  controller.add([4, 5, 6]); // Same result: Not printed again
}
