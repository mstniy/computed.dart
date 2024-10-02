Performant and flexible functional reactive programming for collections.

> [!TIP]
> computed_collections builds on [`computed`](https://pub.dev/packages/computed). Make sure you are familiar with `computed` fundamentals.

---

`computed_collections` allows you to declaratively define reactive collections. It,

- uses [`computed`](https://pub.dev/packages/computed) as the base for strong and consistent reactivity
- uses [`fast_immutable_collections`](https://pub.dev/packages/fast_immutable_collections) for performant and powerful immutable collections
- constructs, transforms and propagates internal change streams to stay efficient
- allows local key queries on all reactive collections
- is designed to be asymptotically optimal for all operations

## <a name='table-of-contents'></a>Table of contents

<!-- vscode-markdown-toc -->

- [Table of contents](#table-of-contents)
- [An example](#an-example)
- [Ingesting external change streams](#ingesting-external-change-streams)
  - [Stateful change streams](#stateful-change-streams)
- [Constant reactive maps](#constant-reactive-maps)
- [Mapping with inter-key dependencies](#mapping-with-inter-key-dependencies)
- [An index of operators](#an-index-of-operators)
- [An index of attributes](#an-index-of-attributes)

<!-- vscode-markdown-toc-config
	numbering=false
	autoSave=true
	/vscode-markdown-toc-config -->
<!-- /vscode-markdown-toc -->

## <a name='an-example'></a>An example

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

Of course, it would be even better to ingest a change stream instead of a snapshot stream, so that we could avoid diffing subsequent snapshots in the first place. Which brings us to...

## <a name='ingesting-external-change-streams'></a>Ingesting external change streams

`computed_collection` is built on change streams. A reactive map, represented with the interface `ComputedMap`, internally has a snapshot and a change stream. Operators, such as `.map`, `.join` and `.removeWhere` use and transform these streams. If you have a change stream computation, you can use the factory function `ComputedMap.fromChangeStream`:

```dart
Computed<ChangeEvent<ObjectId, MyObject>> changes = ...;
final cmap = ComputedMap.fromChangeStream(changes); // has type `ComputedMap<ObjectId, MyObject>`
```

The [`ChangeEvent`](https://pub.dev/documentation/computed_collections/latest/change_event/ChangeEvent-class.html) class represents a set of changes made on a map. Mind you that you might need to write some "glue" code to convert a change stream using an external format into the format used by `computed_collections`. This should not be too difficult with `computed`.

### <a name='stateful-change-streams'></a>Stateful change streams

You might need the conversion from the external change stream to the internal one to be stateful. You can do this using internal sub-computations captured in the change stream computation's closure. But what if the state you need is the snapshot of the collection you are building? A simple use case would be to listen on a stream and incrementing the value of each published key by one. You can do this using `ComputedMap.fromChangeStreamWithPrev`. Analogous to the `computed`'s [`Computed.withPrev`](https://pub.dev/documentation/computed/latest/computed/Computed/Computed.withPrev.html), it passes the collection's previous snapshot to the change stream computation:

```dart
final s = StreamController<int>(sync: true);
final stream = s.stream;
final m = ComputedMap.fromChangeStreamWithPrev((prev){
  final c = KeyChanges(<int, ChangeRecord<int>>{}.lock);
  stream.react((idx) => c[idx] = ChangeRecordValue(prev[idx] ?? 0 + 1));
  return c;
});

m.snapshot.listen(print);

s.add(0); // prints {0:1}
s.add(0); // prints {0:2}
s.add(1); // prints {0:2, 1:1}
```

## <a name='constant-reactive-maps'></a>Constant reactive maps

You can use `ComputedMap.fromIMap` to define a constant reactive map. Then it is not quite so reactive.

```dart
final m1 = ComputedMap.fromIMap({1:2, 2:3}.lock);
final m2 = m1.mapValues((k, v) => v+1); // Is {1:3, 2:4}
m2.snapshot.listen(print); // Prints {1:3, 2:4}
```

## <a name='mapping-with-inter-key-dependencies'></a>Mapping with inter-key dependencies

You can use the operators with `*Computed` in their name to define transformations with arbitrary reactive dependencies. In particular, the transformation of one key can depend on the result of the transformation of another key, like the following program which decleratively computes how many steps each integers in the range $[1,16]$ take to be reduced to 1 in the Collatz conjuncture:

```dart
final m1 = ComputedMap.fromIMap(
    IMap.fromEntries(List.generate(200, (i) => MapEntry(i, 0))));
late final ComputedMap<int, int> m2;
m2 = m1.mapValuesComputed((k, v) => k <= 1
    ? $(() => 0)
    : $(() => m2[((k % 2) == 0 ? k ~/ 2 : (k * 3 + 1))].use! + 1));
final m3 = m1
    .removeWhere((k, v) => k == 0 || k > 16)
    .mapValuesComputed((k, v) => m2[k]);
m3.snapshot.listen(print);
```

This might not be the most performant implementation, but note that it is asymptotically optimal in the sense that it uses memoization. It also showcases the key-local query capabilities, as computing the Collatz sequences of all the integers in the range $[0, 200]$ requires more than 200 indices.

## <a name='an-index-of-operators'></a>An index of operators

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

## <a name='an-index-of-attributes'></a>An index of attributes

Below is a list of attributes on reactive maps along with a high-level description of them.

| Attribute         | Description                                           |
| ----------------- | ----------------------------------------------------- |
| **`.changes`**    | The change stream computation for this map.           |
| **`.snapshot`**   | The snapshot computation for this map.                |
| **`.operator[]`** | A computation representing the given key of this map. |
| **`.isEmpty`**    | A computation representing the emptyness of this map. |
| **`.isNotEmpty`** | Opposite of `.isEmpty`.                               |
| **`.length`**     | A computation representing the length of this map.    |
