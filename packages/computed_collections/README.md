Performant and flexible functional reactive programming for collections.

> [!TIP] > `computed_collections` builds on [`computed`](https://pub.dev/packages/computed). Make sure you are familiar with `computed` fundamentals.

---

`computed_collections` allows you to declaratively define reactive collections. It,

- uses [`computed`](https://pub.dev/packages/computed) as the base for strong and consistent reactivity
- uses [`fast_immutable_collections`](https://pub.dev/packages/fast_immutable_collections) for performant and powerful immutable collections
- constructs, transforms and propagates internal change streams to stay efficient
- allows local key queries on all reactive collections
- is designed to be asymptotically optimal for all operations

### An example

Imagine you want to display in your UI a list of objects. You get the objects from a database or server. However, you only want to display the objects which have recently been modified.

Assuming you have the following:

```dart
Stream<Map<ObjectId, MyObject>> objectsUnfiltered = ...;
void displayInUI(List<MyObject> objects) {
  ...
}
bool isRecent(MyObject object) {
  ...
}
```

Here is how you might approach this problem imperatively:

```dart
objectsUnfiltered
  .listen((o) => displayInUI(o.values.where((oo) => isRecent(oo)).toList()));
```

That was easy enough. But do you see the problem? The listener filters all the objects for every single change. This might not be a problem if you have a small number of objects, or the reactive logic you wish to run is computationally cheap, but such an approach clearly will not scale for a large and complex application.

To alleviate the problem, you can first identify how the unfiltered set of objects was changed and run the reactive logic only on the relevant part of the map:

```dart
({
  Map<ObjectId, MyObject> unfiltered,
  Map<ObjectId, MyObject> filtered
})? lastObjects;

objectsUnfiltered.listen((objs) {
  switch (lastObjects) {
    case var last?:
      final changed =
          last.unfiltered.entries.where((e) => e.value != objs[e.key]);
      final addRemove = groupBy(changed, (e) => isRecent(e.value));
      last.filtered.addEntries(addRemove[true] ?? []);
      for (var e in (addRemove[false] ?? [])) {
        last.filtered.remove(e.key);
      }
      lastObjects = (filtered: last.filtered, unfiltered: objs);
      displayInUI(last.filtered.values.toList());
    case null:
      final filtered =
          Map.fromEntries(objs.entries.where((e) => isRecent(e.value)));
      lastObjects = (filtered: filtered, unfiltered: objs);
      displayInUI(filtered.values.toList());
  }
});
```

Phew. That was a mouthful. We had to maintain a pair of maps are our state: one representing the last set of unfiltered objects and another for the filtered set. For each change in the stream, we compute an upstream delta, if a previous value existed, and update the state and UI accordingly.

You can see how such an architecture can quickly become difficult to maintain. All this was just for an asymptotically optimal, reactive `.where`. Imagine if we needed to use the same upstream for multiple downstream operations, like one `.where` and one `groupBy`. A reactive `groupBy` is already significantly more complex than the case above, but what if we also wanted to "share" the delta we compute across these downstream operations for efficiency's sake?

Let's leave these questions aside and see how such a reactive collection can be implemented using `computed_collections`:

```dart
final unfiltered =
      ComputedMap.fromSnapshotStream($(() => objectsUnfiltered.use.lock));
final filtered = unfiltered.removeWhere((k, v) => !isRecent(v));
filtered.snapshot.listen((s) => displayInUI(s.values.toList()));
```

That's all. `fromSnapshotStream` internally handles the manual diffing we did in the imperative example and construct a _change stream_. `.removeWhere` subscribes to this change stream to incrementally maintain the filtered map. Finally, we use `filtered.snapshot`, which returns a `computed` computation representing the snapshot of the filtered map, on which we attach a listener to update the UI. In this case, we had to use `.lock` on the map we got from the stream to turn it into a [fast immutable map](https://pub.dev/documentation/fast_immutable_collections/latest/fast_immutable_collections/IMap-class.html) as `computed_collections` operates exclusively on them, but this can reasonly be assumed not to harm asymptotical complexity.

### Ingesting external change streams

`computed_collection` is built on change streams. A reactive map, represented with the interface `ComputedMap`, internally has a snapshot and a change stream. Operators, such as `.map`, `.join` and `.removeWhere` use and transform these streams. If you have a change stream computation, you can use the factory function `ComputedMap.fromChangeStream`:

```dart
Computed<ChangeEvent<ObjectId, MyObject>> changes = ...;
final cmap = ComputedMap.fromChangeStream(changes); // has type `ComputedMap<ObjectId, MyObject>`
```

The [`ChangeEvent`](https://pub.dev/documentation/computed_collections/latest/change_event/ChangeEvent-class.html) class represents a set of changes made on a map. Mind you that you might need to write some "glue" code to convert a change stream using an external format into the format used by `computed_collections`. This should not be too difficult with `computed`.

### An index of operators

Below is a list of reactive operators on reactive maps along with a high-level description of them.

| Operator                   | Description                                                                                           |
| -------------------------- | ----------------------------------------------------------------------------------------------------- |
| **`.add`**                 | Reactively adds a given key-value pair to a reactive map.                                             |
| **`.addAll`**              | Reactively adds a given `IMap` to a reactive map.                                                     |
| **`.addAllComputed`**      | Reactively adds a given reactive map to a reactive map.                                               |
| **`.cast`**                | Reactively casts the entries of a reactive map.                                                       |
| **`.containsKey`**         | Returns a computation representing if a reactive map contains a given key.                            |
| **`.containsValue`**       | Returns a computation representing if a reactive map contains a given value.                          |
| **`.map`**                 | Reactively maps each entries of a reactive map by a given synchronous function.                       |
| **`.mapComputed`**         | Reactively maps each entries of a reactive map by a given reactive convertion computation.            |
| **`.mapValues`**           | Reactively maps all values of a reactive map by a given synchronous function.                         |
| **`.mapValuesComputed`**   | Reactively maps all values of a reactive map by a given reactive convertion computation.              |
| **`.putIfAbsent`**         | Reactively adds a given key to a reactive map, if it does not already exist.                          |
| **`.remove`**              | Reactively removes a given key from a reactive map.                                                   |
| **`.removeWhere`**         | Reactively removes all entries satisfying a given synchronous condition from a reactive map.          |
| **`.removeWhereComputed`** | Reactively removes all entries satisfying a given reactive condition computation from a reactive map. |
| **`.update`**              | Reactively transforms a given key of a reactive map by a given synchronous function.                  |
| **`.updateAll`**           | A special case of `.mapValues` where the input and output types are the same.                         |
| **`.updateAllComputed`**   | A special case of `.mapValuesComputed` where the input and output types are the same.                 |
| **`.groupBy`**             | Reactively groups a reactive map by a given synchronous function.                                     |
| **`.groupByComputed`**     | Reactively groups a reactive map by a given reactive group computation.                               |
| **`.join`**                | Computes a reactive inner join of a pair of reactive maps.                                            |
| **`.lookup`**              | Computes a reactive left join of a pair of reactive maps.                                             |
| **`.cartesianProduct`**    | Computes a reactive cartesian product of a pair of reactive maps.                                     |
| **`.flat`**                | Reactively flattens a reactive map of reactive maps.                                                  |

### An index of attributes

Below is a list of attributes on reactive maps along with a high-level description of them.

| Attribute         | Description                                           |
| ----------------- | ----------------------------------------------------- |
| **`.changes`**    | The change stream computation for this map.           |
| **`.snapshot`**   | The snapshot computation for this map                 |
| **`.operator[]`** | A computation representing the given key of this map. |
| **`.isEmpty`**    | A computation representing the emptyness of this map. |
| **`.isNotEmpty`** | Opposite of `.isEmpty`.                               |
| **`.length`**     | A computation representing the length of this map.    |
