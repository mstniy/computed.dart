import 'package:computed/src/computed.dart';
import 'package:computed/stream_extension.dart';
import 'package:computed/utils/streams.dart';
import 'package:test/test.dart';

class _DelayedComputedImpl<T> extends ComputedImpl<T> {
  final void Function() _onDependencyUpdated;
  _DelayedComputedImpl(this._onDependencyUpdated, T Function() build)
      : super(build, false, false, null, null);

  @override
  // Cannot subscribe to delayed computations
  T get use => throw UnimplementedError();

  @override
  T get useWeak => throw UnimplementedError();

  @override
  Set<ComputedImpl> onDependencyUpdated() {
    // Delay until reeval() is called
    _onDependencyUpdated();
    return {};
  }

  void reeval() {
    super.onDependencyUpdated();
  }
}

void main() {
  test('delayed reeval pattern works', () async {
    var odcCnt = 0;
    final s = ValueStream(sync: true);
    final c = _DelayedComputedImpl(() => odcCnt++, () => s.use);

    var lCnt = 0;
    int? lastEvent;

    final sub = c.listen((event) {
      lCnt++;
      lastEvent = event;
    }, (e) => fail(e.toString()));

    s.add(0);
    expect(odcCnt, 1);
    expect(lCnt, 0);
    c.reeval();
    expect(odcCnt, 1);
    expect(lCnt, 1);
    expect(lastEvent, 0);
    s.add(0);
    expect(odcCnt, 1);
    s.add(1);
    expect(odcCnt, 2);
    expect(lCnt, 1);
    c.reeval();
    expect(odcCnt, 2);
    expect(lCnt, 2);
    expect(lastEvent, 1);

    sub.cancel();
  });
}
