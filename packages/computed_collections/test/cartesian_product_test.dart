import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'package:computed_collections/computedmap.dart';

import 'helpers.dart';

void main() {
  test('works', () async {
    final m1 = ComputedMap.fromIMap({0: 1, 2: 3}.lock);
    final m2 = ComputedMap.fromIMap({4: 5, 6: 7}.lock);
    final m3 = m1.cartesianProduct(m2);

    expect(
        await getValue(m3.snapshot),
        {
          (0, 4): (1, 5),
          (0, 6): (1, 7),
          (2, 4): (3, 5),
          (2, 6): (3, 7),
        }.lock);
  });
}
