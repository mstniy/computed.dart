import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

void main() {
  final s = StreamController<ChangeEvent<int, int>>(sync: true);
  final stream = s.stream;

  final m = ComputedMap.fromChangeStream($(() => stream.use))
      .removeWhere((key, value) => key % 2 == 1)
      .updateAll((key, value) => value + 1);

  final sub = Computed.effect(() => print(m.snapshot.use));

  // Prints {}

  s.add(ChangeEventReplace({0: 1, 1: 2, 2: 3}.lock));
  // Prints {0:2, 2:4}

  s.add(
      KeyChanges({0: ChangeRecordValue(0), 2: ChangeRecordDelete<int>()}.lock));
  // Prints {0: 1}

  sub.cancel();
}
