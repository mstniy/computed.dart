import 'dart:async';

class NoValueException {}

class NoSubscriptionException<T> {
  Stream<T> s;
  NoSubscriptionException(this.s);
}

class SubscriptionLastValue<T> {
  StreamSubscription<T> subscription;
  bool hasValue = false;
  T? lastValue;
  SubscriptionLastValue(this.subscription);
}

class ComputedContext {
  final _streams = <Stream, SubscriptionLastValue>{};
  T call<T>(Stream<T> s) {
    final slv = _streams[s];
    if (slv == null) throw NoSubscriptionException(s);
    if (!slv.hasValue) {
      throw NoValueException();
    }
    return slv.lastValue!;
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
  final _ctx = ComputedContext();
  final _listeners = <ComputedSubscription<T>>{};
  var _hasLastResult = false;
  bool get hasLastResult => _hasLastResult;
  T? _lastResult;
  T? get lastResult => _lastResult;
  final T Function(ComputedContext ctx) f;
  Computed(this.f) {
    _evalF();
  }

  void _evalF() {
    late T fRes;
    var fFinished = false;
    try {
      fRes = f(_ctx);
      // cancel subscriptions to unused streams & remove them from the context (bonus: allow the user to specify a duration before doing that)
      fFinished = true;
    } on NoValueException catch (_) {
      // Not much we can do
    } on NoSubscriptionException catch (e) {
      late SubscriptionLastValue slv;
      slv = SubscriptionLastValue(e.s.listen((event) {
        slv.hasValue = true;
        slv.lastValue = event;
        _maybeEvalF();
      })); // Handle onError (passthrough), onDone (close subscriptions to upstreams)
      _ctx._streams[e.s] = slv;
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
    return sub;
  }
}

void main() async {
  final completer = Completer<List<int>>();
  final source =
      Stream<List<int>>.fromFuture(completer.future).asBroadcastStream();

  final anyNegative =
      Computed((ctx) => ctx(source).any((element) => element < 0));

  final maybeReversed = Computed(
      (ctx) => ctx(anyNegative) ? ctx(source).reversed.toList() : ctx(source));

  maybeReversed.listen((value) => print(value));

  completer.complete([1, 2, -3]);
}
