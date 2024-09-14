import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('attributes are coherent', () async {
    final m = ComputedMap.fromIMap({0: 1}.lock);
    final a = m.putIfAbsent(0, () => 0);
    final b = a.putIfAbsent(1, () => 1);
    await testCoherenceInt(a, {0: 1}.lock);
    await testCoherenceInt(b, {0: 1, 1: 1}.lock);
  });
}
