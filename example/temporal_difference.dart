import 'dart:async';

import 'package:computed/computed.dart';

void main() {
  final cont = StreamController<int>.broadcast(sync: true);
  final s = cont.stream;
  final c = $(() {
    s.use; // Make sure it has a value
    late int res;
    s.react((val) => res = val - s.prevOr(0));
    return res;
  }, memoized: false);

  Computed.effect(() => print(c.use));

  cont.add(1);
  cont.add(1);
  cont.add(2);
  cont.add(3);
  cont.add(6);
  cont.add(3);
}
