This folder hosts a minimal set of `Stream`s which are likely to be useful in a reactive setting.

Note that these classes are not exclusive to Computed, as they are Dart `Stream`s after all. They are, however, designed with Computed in mind, and consuming them from inside a computation merely requires a `.use`, as with any other `Stream`.

### 1. <a name='`valuestream`'></a>`ValueStream`

A `Stream` with last value semantics, similar to Flutter's `ValueNotifier` or rxdart's `BehaviorSubject`:

```
final s = ValueStream<int>();
s.add(0);
s.add(0);                 // Ignored: the last added value is already 0
s.addError(StateError()); // Can add errors
```

You can also pass an initial value:

```
final s = ValueStream.seeded(0);
```

Note that `ValueStream` does not provide a way to get the last value synchronously. This is intentional, as this would be an easy way to break your application's reactivity.

### 2. <a name='`resourcestream`'></a>`ResourceStream`

A `ValueStream`, where the values are resources created by a given function, and need to be disposed of by another given function:

```
final s = ResourceStream<FictionalDatabase>(
    () => FictionalDatabase(),
    (db) => db.dispose()
);

final sub = s.listen(...);  // Creates a `FictionalDatabase`
s.add(FictionalDatabase()); // Disposes of the first one
sub.cancel();               // Disposes of the second one

final c = $(() => s.use.getVersion());
c.listen(...);              // Creates a new `FictionalDatabase`
```
