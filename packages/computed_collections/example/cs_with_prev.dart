import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

void main() {
  final s = StreamController<int>(sync: true);
  final stream = s.stream;
  final m = ComputedMap<int, int>.fromChangeStreamWithPrev((prev) {
    var c = KeyChanges(<int, ChangeRecord<int>>{}.lock);
    stream.react((idx) => c = KeyChanges({
          idx: ChangeRecordValue(((prev ?? <int, int>{}.lock)[idx] ?? 0) + 1)
        }.lock));
    return c;
  });

  m.snapshot.listen(print);

  s.add(0); // prints {0:1}
  s.add(0); // prints {0:2}
  s.add(1); // prints {0:2, 1:1}
}
