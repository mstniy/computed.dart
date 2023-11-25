import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:computed/computed.dart';

void main() async {
  final controller = StreamController<BuiltList<int>>(
      sync: true); // Use a sync controller to make debugging easier
  final source = controller.stream.asBroadcastStream();

  final anyNegative = Computed(() => source.use.any((element) => element < 0));

  final maybeReversed = Computed(
      () => anyNegative.use ? source.use.reversed.toBuiltList() : source.use);

  final append0 = Computed(() {
    return maybeReversed.use.rebuild((p0) => p0.add(0));
  });

  append0.listen((value) => print(value));

  // ignore: unused_local_variable
  final unused = Computed(() {
    while (true) {
      print("Never prints, this computation is never used.");
    }
  });

  controller.add([1, 2, -3, 4].toBuiltList()); // prints [4, -3, 2, 1, 0]
  controller.add([1, 2, -3, -4].toBuiltList()); // prints [-4, -3, 2, 1, 0]
  controller.add([4, 5, 6].toBuiltList()); // prints [4, 5, 6, 0]
  controller.add([4, 5, 6].toBuiltList()); // Same result: Not printed again
}
