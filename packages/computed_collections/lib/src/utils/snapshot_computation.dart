import 'package:computed/computed.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../change_event.dart';

Computed<IMap<K, V>> snapshotComputation<K, V>(
    Computed<ChangeEvent<K, V>> changes,
    IMap<K, V> Function()? _initialValueComputer) {
  final firstReactToken = IMap<K,
      V>(); // TODO: This is obviously ugly. Make Computed.withPrev support null instead
  return Computed.withPrev((prev) {
    if (identical(prev, firstReactToken)) {
      if (_initialValueComputer != null) {
        prev = _initialValueComputer();
      } else {
        prev = <K, V>{}.lock;
      }
    }

    try {
      return prev.withChange(changes.use);
    } on NoValueException {
      return prev;
    }
  }, async: true, initialPrev: firstReactToken);
}
