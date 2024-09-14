import 'package:computed/computed.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('attributes are coherent', () async {
    final m = ComputedMap.fromIMap({0: 1}.lock);
    final mv = m.updateAllComputed((key, value) => $(() => value + 1));
    await testCoherenceInt(mv, {0: 2}.lock);
  });
}
