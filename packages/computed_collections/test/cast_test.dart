import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

abstract class A {}

class B extends A {
  @override
  bool operator ==(Object o) => o is B;

  @override
  int get hashCode => 0;
}

class C {
  @override
  bool operator ==(Object o) => o is C;

  @override
  int get hashCode => 1;
}

void main() {
  test('works', () async {
    final a = ComputedMap.fromIMap({0: B()}.lock);
    final b = a.cast<int, A>();
    final c = b.cast<int, B>();
    expect(await getValue(b.snapshot), <int, A>{0: B()}.lock);
    expect(await getValue(c.snapshot), {0: B()}.lock);
  });
  test('throws if a cast fails', () async {
    final a = ComputedMap.fromIMap({0: B()}.lock);
    final b = a.cast<int, C>();
    try {
      await getValue(b.snapshot);
      fail("Must have thrown");
    } catch (e) {
      expect(e, isA<TypeError>());
      expect(
          e.toString(), "type 'B' is not a subtype of type 'C' in type cast");
    }
  });
  test('attributes are coherent', () async {
    final m = ComputedMap.fromIMap({0: 1}.lock);
    final a = m.cast<int, int>();
    await testCoherenceInt(a, {0: 1}.lock);
  });
}
