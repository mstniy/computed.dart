import 'dart:async';
import 'dart:math' as math;

import 'package:built_collection/built_collection.dart';
import 'package:computed/computed.dart';
import 'package:tuple/tuple.dart';

typedef TodoItem = String;

typedef AppState = BuiltMap<int, TodoItem>;

class FictionaryDatabase {
  AppState? _state;
  final _stateStream = StreamController<AppState>.broadcast();
  Stream<AppState> loadState() async* {
    if (_state == null) {
      print('Reading DB...');
      _state = AppState({0: "todo1"});
    }
    yield _state!;
    yield* _stateStream.stream;
  }

  // In a real-world application, a reactive db would provide this functionality
  Stream<int> largestIdQuery() async* {
    await for (var state in loadState()) {
      yield state.isEmpty ? 0 : state.keys.reduce(math.max);
    }
  }

  // Simulates the database mysteriously changing, eg. by another tab on web
  void injectState(AppState state) {
    if (_state == state) return;
    _state = state;
    _stateStream.add(state);
  }

  Future<void> saveState(AppState state) {
    print('DB saving state: $state');
    injectState(state);
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

  final dbStream = db.loadState().asBroadcastStream();

  final largestIdStream = db.largestIdQuery();

  final appState = Computed<AppState>.withPrev((prev) {
    // Apply UI or DB changes, if there are any
    return prev.rebuild(
      (b) {
        dbStream.react(b.replace);
        uiDelete.react(b.remove);
        uiUpdate.react((t) {
          b[t.item1] = t.item2;
        });
        final id = largestIdStream.use + 1;
        uiCreate.react((t) {
          b[id] = t;
        });
      },
    );
  }, initialPrev: await dbStream.first);

  final stateIsInitial = Computed.withPrev(
      (prev) => Tuple2(prev == null, appState.use),
      initialPrev: null);

  stateIsInitial.listen((state) {
    // Do not save the initial state
    if (!state!.item1) db.saveState(state.item2);
  }, (e) => print('Exception: ${e.toString()}'));

  uiCreateController.add('new todo');
  await Future.delayed(Duration.zero);
  uiDeleteController.add(0);
  await Future.delayed(Duration.zero);
  uiUpdateController.add(Tuple2(1, 'new todo edited'));
  await Future.delayed(Duration.zero);
  uiDeleteController.add(1);
  await Future.delayed(Duration.zero);
  db.injectState({2: 'mysterious todo'}.build());
  await Future.delayed(Duration.zero);
  uiCreateController.add('newer todo');
  await Future.delayed(Duration.zero);
  uiUpdateController.add(Tuple2(2, 'mysterious todo edited'));
}
