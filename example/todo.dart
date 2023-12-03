import 'dart:async';
import 'dart:math' as math;

import 'package:built_collection/built_collection.dart';
import 'package:computed/computed.dart';
import 'package:tuple/tuple.dart';

typedef TodoItem = String;

typedef AppState = BuiltMap<int, TodoItem>;

class FictionaryDatabase {
  Future<AppState?> loadState() {
    // 1 second delay for dramatic effect
    print('Reading DB...');
    return Future.delayed(
        const Duration(seconds: 1), () => AppState({0: "todo1"}));
  }

  Future<void> saveState(AppState state) {
    print('DB saving state: $state');
    return Future.value();
  }
}

final db = FictionaryDatabase();

void main() async {
  final uiDeleteController = StreamController<int>(
      sync: true); // Use a sync controller to make debugging easier
  final uiDelete = uiDeleteController.stream;
  final uiUpdateController = StreamController<Tuple2<int, TodoItem>>(
      sync: true); // Use a sync controller to make debugging easier
  final uiUpdate = uiUpdateController.stream;

  final uiCreateController = StreamController<TodoItem>(
      sync: true); // Use a sync controller to make debugging easier
  final uiCreate = uiCreateController.stream;

  final dbFuture = db.loadState();
  final largestId = Computed<int>.withPrev((prev) {
    var id = prev;
    uiCreate.react((p0) => id++, null);

    return id;
  },
      initialPrev:
          ((await dbFuture) ?? BuiltMap<int, String>()).keys.reduce(math.max));

  final appState = Computed<AppState>.withPrev((prev) {
    // Apply UI changes, if there are any
    return prev.rebuild(
      (b) {
        uiDelete.react((id) {
          b.remove(id);
        }, null);
        uiUpdate.react((t) {
          b[t.item1] = t.item2;
        }, null);
        final id = largestId.use;
        uiCreate.react((t) {
          b[id] = t;
        }, null);
      },
    );
  }, initialPrev: (await dbFuture) ?? AppState());

  final stateIsInitial = Computed.withPrev(
      (prev) => Tuple2(prev == null, appState.use),
      initialPrev: null);

  stateIsInitial.listen((state) {
    // Do not save the initial state
    if (!state!.item1) db.saveState(state.item2);
  }, (e) => print('Exception: ${e.toString()}'));

  await Future.delayed(const Duration(seconds: 2));

  await Future.value();
  uiCreateController.add('new todo');
  await Future.value();
  uiDeleteController.add(0);
  await Future.value();
  uiUpdateController.add(Tuple2(1, 'new todo edited'));
  await Future.value();
  uiDeleteController.add(1);
  await Future.value();
}
