import 'package:computed/computed.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

void main() {
  final m1 = ComputedMap.fromIMap(
      IMap.fromEntries(List.generate(200, (i) => MapEntry(i, 0))));
  late final ComputedMap<int, int> m2;
  m2 = m1.mapValuesComputed((k, v) => k <= 1
      ? $(() => 0)
      : $(() => m2[((k % 2) == 0 ? k ~/ 2 : (k * 3 + 1))].use! + 1));
  final m3 = m1
      .removeWhere((k, v) => k == 0 || k > 16)
      .mapValuesComputed((k, v) => m2[k]);
  m3.snapshot.listen(print);
}
