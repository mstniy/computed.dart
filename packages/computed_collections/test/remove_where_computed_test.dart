import 'package:computed/computed.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // As removeWhereComputed is implemented in terms of other operators, it is sufficient that we run a simple smoke test.
  test('attributes are coherent', () async {
    final m = IComputedMap({0: 1, 1: 1}.lock);
    final mv = m.removeWhereComputed((key, value) => $(() => key == value));
    await testCoherenceInt(mv, {0: 1}.lock);
  });
}
