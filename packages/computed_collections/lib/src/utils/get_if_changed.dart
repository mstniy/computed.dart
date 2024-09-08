import 'package:computed/computed.dart';

T? getIfChanged<T>(Computed<T> c) {
  final T prev;
  final T cur;

  try {
    cur = c.use;
  } on NoValueException {
    // No value yet
    return null;
  }

  try {
    prev = c.prev;
  } on NoValueException {
    return cur;
  }

  if (!identical(prev, cur)) {
    return cur;
  }

  return null;
}
