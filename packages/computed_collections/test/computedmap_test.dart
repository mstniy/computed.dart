import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

Future<V> getValue<V>(Computed<V> c) async {
  late V val;
  Object? err;
  var gotValue = false;
  var gotErr = false;
  final sub = c.listen((event) {
    gotValue = true;
    val = event;
  }, (e) {
    gotErr = true;
    err = e;
  });
  await Future.value(); // So that the listener runs
  expect(gotValue || gotErr, true);
  expect(gotValue && gotErr, false);
  sub.cancel();
  if (gotErr) throw err!;
  return val;
}

void main() {
  test('works', () async {
    final s = ValueStream.seeded({0: 1, 3: 4}.lock);
    final m =
        ComputedMap<int, int>((prev) => s.use, initialPrev: <int, int>{}.lock);
    expect(await getValue(m.snapshot), {0: 1, 3: 4}.lock);
  });
}
