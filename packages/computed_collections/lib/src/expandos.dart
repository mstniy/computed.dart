import 'package:computed/computed.dart';

final isEmptyExpando = Expando<Computed<bool>>('computed_collections::isEmpty');
final isNotEmptyExpando =
    Expando<Computed<bool>>('computed_collections::isNotEmpty');
final lengthExpando = Expando<Computed<int>>('computed_collections::length');
final snapshotExpando = Expando('computed_collections::snapshot');
final changesExpando = Expando('computed_collections::changes');
