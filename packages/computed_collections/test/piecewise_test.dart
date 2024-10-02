import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class IntegerIterator implements Iterator<int> {
  int x;

  IntegerIterator(this.x);

  @override
  int get current => x;

  @override
  bool moveNext() {
    x++;
    return true;
  }
}

class NaturalNumbers with Iterable<int> {
  @override
  Iterator<int> get iterator => IntegerIterator(-1);

  @override
  bool contains(Object? o) => o is int && o >= 0;

  @override
  int get length => throw RangeError('Natural numbers are infinite');
}

void main() {
  test('attributes are coherent', () async {
    await testCoherenceInt(
        ComputedMap.fromPiecewise([1, 2, 3], (key) => key * key),
        {1: 1, 2: 4, 3: 9}.lock);

    await testCoherenceInt(
        ComputedMap.fromPiecewise([], (key) => key), <int, int>{}.lock);
  });

  test('works over infinite domains', () async {
    final m = ComputedMap.fromPiecewise(NaturalNumbers(), (key) {
      return key - 1;
    });

    expect(await getValues(m.changes), []);
    expect(await getValue(m.isEmpty), false);
    expect(await getValue(m.isNotEmpty), true);
    expect(await getValue(m.containsKey(0)), true);
    expect(await getValue(m.containsKey(1)), true);
    expect(await getValue(m.containsKey(-1)), false);
    // Note that we cannot test the case where containsValue should return false
    expect(await getValue(m.containsValue(-1)), true);
    expect(await getValue(m.containsValue(0)), true);
    expect(await getValue(m[0]), -1);
    expect(await getValue(m[1]), 0);
    expect(await getValue(m[-1]), null);
  });
}
