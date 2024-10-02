import 'package:computed/computed.dart';
import 'package:computed_collections/computedmap.dart';

Iterable<int> naturalNumbers() sync* {
  var x = 0;
  while (true) {
    yield x++;
  }
}

void main() {
  final naturals = ComputedMap.fromPiecewise(naturalNumbers(), (_) => 0);
  final domain = ComputedMap.fromPiecewise(
      Iterable<int>.generate(16, (x) => x + 1), (_) => 0);
  late final ComputedMap<int, int> collatz;
  // We cannot define `collatz` by as a transformation of `domain`,
  // as computing the Collatz sequence of an integer may require
  // accessing the sequence for larger integers.
  collatz = naturals.mapValuesComputed((k, v) => k <= 1
      ? $(() => 0)
      : $(() => collatz[((k % 2) == 0 ? k ~/ 2 : (k * 3 + 1))].use! + 1));
  // We define a `rangedCollatz` as `collatz` is an infinite collection.
  // Note that we cannot use `.removeWhere`, as that propagates `.snapshot`
  // calls, and we cannot compute the snapshot of an infinite collection.
  final rangedCollatz = domain.mapValuesComputed((k, v) => collatz[k]);
  rangedCollatz.snapshot.listen(print);
}
