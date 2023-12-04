import 'dart:async';

import 'package:computed/computed.dart';

void main() async {
  final cont = StreamController<int>.broadcast(sync: true);
  final s = cont.stream;
  Computed<int>.withPrev((prev) {
    var res = prev;
    s.react((val) => res += val);
    return res;
  }, initialPrev: 0)
      .listen((event) => print(event), (e) {
    print('Exception: $e');
  });

  await Future.value();
  cont.add(1);
  cont.add(2);
  cont.add(3);
  cont.add(4);
}
