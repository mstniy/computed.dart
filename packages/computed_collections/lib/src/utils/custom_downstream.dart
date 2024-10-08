import 'package:computed/computed.dart';
// ignore: implementation_imports
import 'package:computed/src/computed.dart';

class CustomDownstream extends ComputedImpl<void> {
  final Set<Computed> _downstream;
  CustomDownstream(Set<Computed> Function() f, this._downstream)
      : super(() {
          _downstream.clear();
          _downstream.addAll(f());
        }, false, false, false, null, null);

  @override
  Set<Computed> eval() {
    super.eval();
    return _downstream;
  }
}
