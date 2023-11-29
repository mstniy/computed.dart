A straightforward, reliable, performant and testable reactive state management solution for Dart.

> [!TIP]
> Are you using Flutter? Then make sure to check out [Computed Flutter](https://github.com/mstniy/computed_flutter).

[![Workflow Status](https://github.com/mstniy/computed.dart/actions/workflows/tests.yml/badge.svg)](https://github.com/mstniy/computed.dart/actions?query=branch%3Amaster+workflow%3Atests) [![codecov](https://codecov.io/github/mstniy/computed.dart/graph/badge.svg?token=VVG1YCC1FL)](https://codecov.io/github/mstniy/computed.dart)

---

Computed makes it a breeze to write code that reacts to external events. Just define how you compute your app state based on external data sources, and what effects you want as a result, and Computed will take care of everything else, allowing you to define your app state decleratively, rather than imperatively.

Computed:

- Automatically discovers and tracks computations' dependencies
- Re-computes the computations when needed
- Memoizes computation results
- Defers computations as much as possible
- Runs the computations in a topologically-consistent order upon external events.
- Allows you to reliably test your app's logic with no boilerplate.

## <a name='Tableofcontents'></a>Table of contents

<!-- vscode-markdown-toc -->

- [Here's how it works](#Hereshowitworks)
- [A larger example](#Alargerexample)
- [Testing](#Testing)
- [Looking at the past](#Lookingatthepast)
- [A more complete example](#Amorecompleteexample)
- [FAQ](#FAQ)
- [Pitfalls](#Pitfalls)
  - [Do not use mutable values in computations](#Donotusemutablevaluesincomputations)

<!-- vscode-markdown-toc-config
	numbering=false
	autoSave=true
	/vscode-markdown-toc-config -->
<!-- /vscode-markdown-toc -->

## <a name='Hereshowitworks'></a>Here's how it works

Assume you have a data source, like a `Stream` representing a series of external events:

```
Stream<int> s;
```

And a database to which you would like to persist your state:

```
FictionaryDatabase db;
```

Assume for the sake of example that your business logic is to multiply the received number by two, and write it to the database.

Here is how you can do this using Computed:

```
final c = Computed(() => s.use * 2);
final sub = c.asStream.listen((res){
    db.write(res);
});
```

That's it. Computed will take care of re-running the computation and calling the listener as needed. Note how you did not need to specify a dependency list for the computation, Computed discovers it automatically. You don't even have any mutable state in your app code.

You can also have computations which use other computations' results:

```
final cPlus1 = Computed(() => c.use + 1);
```

## <a name='Alargerexample'></a>A larger example

Assume you have two data sources, one is a stream of integers:

```
Stream<int> threshold;
```

And the other is a stream of lists of integers:

```
Stream<List<int>> items;
```

Assume for the sake of example that your business logic requires you to filter the items in the second stream by the threshold specified by the first stream, and save the results to a database.

Here is how you might approach this problem using an imperative approach.

First you define your state:

```
int? currentThreshold;
List<int> currentUnfilteredItems;
```

Followed by setting up listeners:

```
threshold.listen((value) => {
    if (value == currentThreshold) return ;
    currentThreshold = value;
    updateDB();
});
items.listen((value) => {
    currentUnfilteredItems = value;
    updateDB();
});
```

And your state computation logic:

```
void updateDB() {
    final filteredItems = currentUnfilteredItems.
        filter((x) => x > currentThreshold).
        toList();
    db.write(filteredItems);
}
```

And here is how to do the same using Computed:

```
Computed(() {
    final currentThreshold = threshold.use;
    return items.use.
        filter((x) => x > currentThreshold).
        toList();
}).asStream.listen(db.write);
```

## <a name='Testing'></a>Testing

Computed lets you mock any computation or data source, allowing you to easily test downstream behaviour.

Here is how you could test a situation where the threshold was a set value in the previous example:

```
threshold.mockEmit(42); // Downstream behaves as if 42 was emitted
```

You can also mock computations:

```
c.fix(42);                    // Will always return 42
c.fixThrow(FooException());   // Will always throw FooException
c.mock(() => dataSource.use); // Can mock to arbitrary computations
```

You can undo the mock at any time to return to the original computation:

```
c.unmock();
```

These actions will trigger a re-computation if necessary.

## <a name='Lookingatthepast'></a>Looking at the past

`.use` returns the current value of the data source or computation, so how can you look at the past without resorting to keeping mutable state in your app code? `.prev` allows you to obtain the last value assumed by a given data source or computation the last time the current computation changed its value.

Here is a simple example that computes the difference between the old and new values of a data source whenever it produces a value:

```
final c = Computed(() => s.react - s.prev);
```

Note that the listeners of this computations or other computations using the result of this computation will not be notified if the difference does not change, as computation results are memoized. If this behaviour is not suitable for your application logic, you can return a counter along with the value itself.

You can also create temporal accumulators:

```
final sum = Computed.withSelf((self) {
    try {
        return self.prev + s.react;
    } on NoValueException {
        // Thrown for the first value produced by the stream
        // as self.prev has no value
        return s.react;
    }
});
```

Note the use of `.react` instead of `.use` in these examples.
`.react` marks the current computation to be recomputed for all values produced by a data source, even if it consecutively produces a pair of values comparing `==`. Note that unlike `.use`, `.react` will throw a NoValueException if the data source has not produced a new data or error since the last time the current computation changed value. As a rule of thumb, you should use `.react` over `.use` for data sources representing a sequence of events rather than a state.

## <a name='Amorecompleteexample'></a>A more complete example

In a real world application, it is likely that you will have multiple data and event sources, like a user interface and a local database. Imagine you are developing the canonical todo app. The state should be read from a local database during startup, if one exists, otherwise it should be set to a pre-defined initial value. After startup, the user should be able to manipulate the state using the UI. Let's see how such a complex interaction can be implemented using Computed.

For the sake of simplicity, we define the state of the app at any point in time solely by the set of todo items:

```
typedef AppState = BuiltMap<String, TodoItem> todos; // Keyed by object ids
```

Note that in this example we are using immutable collections from the `built_collection` package, but Computed has no inherent dependency on it.

We will assume we have a local database from which we will load the state during startup:

```
abstract class FictionaryDatabase {
    Future<AppState?> loadState(); // Resolves to null if no state is saved
    Future<void> saveState(AppState state);
}

FictionaryDatabase db;
```

And assume we have created the following streams and our UI pushes data to them whenever the user wishes to make changes to the data:

```
Stream<String> uiDelete;
Stream<TodoItem> uiUpsert;
```

The first step is to create a computation which defines the current state of the app. During app startup, the state comes from the database, unless this is the first startup, in which case it is set to an initial value. After the startup, the state can get modified by the data streams produced by the UI:

```
final appState = Computed.withSelf((self){
    try {
        self.prev; // Check if we have a state
    } on NoValueException {
        // We have no state, so we are starting up.
        // Load the state from the database,
        // if it exists. Otherwise, set it to an empty collection.
        return database.loadState().use ?? AppState();
    }
    // We have a state, so this is not startup.
    // Then this is an update coming from the UI
    // Apply them
    var state = self.prev;
    try {
        state = state.rebuild((b) =>
            b.remove(uiDelete.react));
    } on NoValueException {
        // Pass
    }
    try {
        state = state.rebuild((b) =>
            b[uiUpsert.react.id] = uiUpsert.react);
    } on NoValueException {
        // Pass
    }

    return state;
});
```

We also define a computation that skips the first value of the app state, as we don't want to persist the state we read/initialized during startup:

```
final stateToPersist = Computed((){
    // Throw and do not produce a value if
    // this is the first value of [appState].
    appState.prev;
    // Otherwise, return the current value of [appState].
    return appState.use;
});
```

Then we attach a listener which will persist the state to the database:

```
stateToPersist.listen(
    (state) => db.saveState,
    (e) => print('Exception:', e));
```

## <a name='FAQ'></a>FAQ

- Q: How to pass an async function into `Computed`?
- A: Short answer is: you can't. The functions passed to `Computed` should be pure computations, free of side effects. If you are meaning to use an external value as part of the computation, see `.use`. If you want to react to a stream of external events, see `.react`. If you wish to produce external side effects, see `.listen` or `.as[Broadcast]Stream`.

## <a name='Pitfalls'></a>Pitfalls

### <a name='Donotusemutablevaluesincomputations'></a>Do not use mutable values in computations

Especially if conditionals depending on them are guarding `.use` expressions. Here is an example:

```
Stream<int> value;
var b = false;

final c = Computed(() => b ? value.use : 42);
```

As this may cause Computed to stop tracking `value`, breaking the reactivity of the computation.
