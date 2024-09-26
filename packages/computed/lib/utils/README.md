This folder hosts a minimal set of `Stream`s which are likely to be useful in a reactive setting.

Note that these classes are not exclusively available to Computed, as they are Dart `Stream`s after all. They are, however, designed with Computed in mind. Consuming them from inside a computation merely requires a `.use`, as with any other `Stream`.

### `ValueStream`

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
