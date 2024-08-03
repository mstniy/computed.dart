import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('attributes are coherent', () async {
    final c = IComputedMap({0: 1}.lock);
    await testCoherenceInt(c, {0: 1}.lock);
  });
}