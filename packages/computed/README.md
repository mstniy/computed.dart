A performant and flexible reactive programming framework for Dart.

> [!TIP]
> Are you using Flutter? Then make sure to check out [Computed Flutter](https://github.com/mstniy/computed_flutter).

---

Computed makes it a breeze to express state that stays coherent in response to external events. Just define how you compute your state based on external data sources, and what effects you want as a result, and Computed will take care of everything else, allowing you to handle reactivity declaratively, rather than imperatively.

Computed:

- Integrates with all the standard data sources and sinks (`Future` and `Stream` on Dart, `Listenable` and `ValueListenable` on Flutter with Computed Flutter)
- Can be extended to include support for new data sources and sinks (Computed Flutter extends Computed to add support for Flutter-specific types)
- Automatically discovers and tracks computations' dependencies
- Re-computes the computations when needed
- Memoizes computation results
- Defers computations as much as possible
- Runs the computations in a topologically-consistent order upon external events.
- Avoids re-running computations unless their upstream change.

## <a name='table-of-contents'></a>Table of contents

<!-- vscode-markdown-toc -->

- [Table of contents](#table-of-contents)
- [Here is how it works](#here-is-how-it-works)
- [A larger example](#a-larger-example)
- [Computation Configs](#computation-configs)
  - [`memoized`](#`memoized`)
  - [`assertIdempotent`](#`assertidempotent`)
  - [`async`](#`async`)
  - [`dispose`](#`dispose`)
  - [`onCancel`](#`oncancel`)
- [Effects](#effects)
- [Looking at the past](#looking-at-the-past)
- [Computed queries](#computed-queries)
- [Stream utilities](#stream-utilities)
- [`ComputationCache`](#`computationcache`)
- [Advanced usage](#advanced-usage)
  - [Using computations opportunistically](#using-computations-opportunistically)
  - [Customizing downstream](#customizing-downstream)
- [FAQ](#faq)
- [Pitfalls](#pitfalls)
  - [Do not use mutable values in computations](#do-not-use-mutable-values-in-computations)
  - [Use the async mode for computations kicking off async operations](#use-the-async-mode-for-computations-kicking-off-async-operations)
  - [Do not `.use` a `Future`s or `Stream` inside the computation that created it](#do-not-`.use`-a-`future`s-or-`stream`-inside-the-computation-that-created-it)
  - [Do not `.use` a computation inside the computation that created it](#do-not-`.use`-a-computation-inside-the-computation-that-created-it)
  - [`Future`s returned from computations are not awaited](#`future`s-returned-from-computations-are-not-awaited)
  - [Do not forget to `.use` or `.react` your data sources](#do-not-forget-to-`.use`-or-`.react`-your-data-sources)
  - [Keep in mind that `.prev` does not subscribe](#keep-in-mind-that-`.prev`-does-not-subscribe)
  - [`.react` is not `.listen`](#`.react`-is-not-`.listen`)

<!-- vscode-markdown-toc-config
	numbering=false
	autoSave=true
	/vscode-markdown-toc-config -->
<!-- /vscode-markdown-toc -->

## <a name='here-is-how-it-works'></a>Here is how it works

Assume you have a data source, like a `Stream` representing a series of external events:

```dart
Stream<int> s;
```

And a database to which you would like to persist your state:

```dart
FictionaryDatabase db;
```

Assume for the sake of example that your business logic is to multiply the received number by two, and write it to the database.

Here is how you can do this using Computed:

```dart
final sub = $(() => s.use * 2).
  listen(db.write);
```

That's it. Computed will take care of re-running the computation and calling the listener as needed. Note how you did not need to specify a dependency list for the computation, Computed discovers it automatically. You don't even have any explicit mutable state in your code.

To cancel the listener, you can use `.cancel()`:

```dart
sub.cancel();
```

You can also have computations which use other computations' results:

```dart
final cPlus1 = $(() => c.use + 1);
```

## <a name='a-larger-example'></a>A larger example

Assume you have two data sources, one is a stream of integers:

```dart
Stream<int> threshold;
```

And the other is a stream of lists of integers:

```dart
Stream<List<int>> items;
```

Assume for the sake of example that you want to implement some logic requiring you to filter the items in the second stream by the threshold specified by the first stream, and save the results to a database.

Here is how you might approach this problem using an imperative approach.

First you define your state:

```dart
int? currentThreshold;
var currentUnfilteredItems = <int>[];
```

Followed by setting up listeners:

```dart
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

```dart
void updateDB() {
    if (currentThreshold == null) return ;
    final filteredItems = currentUnfilteredItems.
        filter((x) => x > currentThreshold).
        toList();
    db.write(filteredItems);
}
```

And here is how to do the same using Computed:

```dart
Computed(() {
    final currentThreshold = threshold.use;
    return items.use.
        filter((x) => x > currentThreshold).
        toList();
}, assertIdempotent: false).listen(db.write);
```

Note that use of [`assertIdempotent: false`](#assertidempotent), as `List` does not have value semantics around its equality operator. In general, [`computed_collections`](https://github.com/mstniy/computed.dart/tree/master/packages/computed_collections) is the better solution for expressing reactive collections.

## <a name='computation-configs'></a>Computation Configs

The shorthand `$` notation used in the previous examples is a quick way of expressing "pure" reactive computations, computations which are idempotent with respect to the equality operator of the result and have no side effects. Computed also allows you to express computations which are not idempotent and/or have side effects using the following configuration parameters:

### <a name='`memoized`'></a>`memoized`

If set to `true` (default), Computed "memoizes" the value of this computation, skipping to notify the downstream/listeners if this computation returns a value or throws an exception comparing equal to the previous one.

### <a name='`assertidempotent`'></a>`assertIdempotent`

If set to `true` (default), Computed runs this computation twice initially and in response to upstream changes in debug mode and checks if the two runs return equal values or throw equal exceptions. If not, it asserts.

### <a name='`async`'></a>`async`

If set to `false` (default), Computed runs this computation in a [Zone](https://dart.dev/libraries/async/zones) that disallows async operations. Setting this to `true` implies `assertIdempotent==false`.

### <a name='`dispose`'></a>`dispose`

If set, this callback is called with the last value returned by the computation when it:

- changes value,
- switches from producing values to throwing exceptions or
- loses all of its listeners and non-weak downstream computations,

if it previously had a value.

### <a name='`oncancel`'></a>`onCancel`

If set, this callback be called when the computation loses all of its listeners and non-weak downstream computations. Called after `dispose`.

## <a name='effects'></a>Effects

Effects allow you to define computations with side effects. Like `.listen`, effects ultimately trigger the computation graph for the computations they use.  
Effects are particularly useful if you wish to define side effects depending on multiple data sources or computations:

```dart
Stream<PageType> activePage;
Stream<bool> isDarkMode;

final sub = Computed.effect(() => sendAnalytics(activePage.use, isDarkMode.use));
```

Like listeners effects can be cancelled with `.cancel()`:

```dart
sub.cancel();
```

## <a name='looking-at-the-past'></a>Looking at the past

`.use` returns the current value of the data source or computation, so how can you look at the past without resorting to keeping mutable state in your app code? `.prev` allows you to obtain the last value assumed by a given data source or computation the last time the current computation ran.

Here is a simple example that computes the difference between the old and new values of a data source whenever it produces a value:

```dart
final c = $(() {
    s.use; // Make sure it has a value
    late int res;
    s.react((val) => res = val - s.prevOr(0));
    return res;
}, memoized: false);
```

Note the use of `.react` in this example.
`.react` marks the current computation to be recomputed for all values produced by a data source, even if it consecutively produces a pair of values comparing `==`. `.react` will run the given function if the data source has produced a new value/error. As a rule of thumb, you should use `.react` over `.use` for data sources representing a sequence of events rather than a state.  
`.prevOr` is a handy shortcut which returns the given fallback value instead of throwing `NoValueException` if the data source had no value the last time the current computation notified its listeners or other computations which depend on it.  
[`memoized: false`](#memoized) prevents the result of the computation from being memoized, as we want the downstream computations and listeners to be notificed even if the difference did not change.

You can also create temporal accumulators:

```dart
final sum = Computed<int>.withPrev((prev) {
    var res = prev;
    s.react((val) => res += val);
    return res;
}, initialPrev: 0);
```

## <a name='computed-queries'></a>Computed queries

Your application might need to run queries with computed state as its parameters. You can achieve this using "async" computations and `unwrap`:

```dart
class FictionaryDatabase {
    Future<List<Object>> filterByCategory(int category, bool includeDeleted);
}

Stream<int> category; // Assume connected to the UI
Stream<bool> includeDeleted; // Assume connected to the UI
FictionaryDatabase db; // Assume connected to a database

final query = Computed.async(() =>
  db.filterByCategory(category.use, includeDeleted.use)).unwrap;
```

Using `Computed.async` disables some checks which don't apply for computations starting asynchronous operations.  
`unwrap` returns a computation representing the last value produced by the last asynchronous operation returned by the computation it is applied to. In this example, it converts the computation from the type `Computed<Future<int>>` to `Computed<int>`.  
`unwrap` is defined for computations returning `Stream` and `Future`, so the computation in the example would also work if the database returned a `Stream` instead of a `Future`. A database supporting reactive queries might do that.  
Of course, other computations can use the result of the computed query, as it is a computation itself.

## <a name='stream-utilities'></a>Stream utilities

Computed includes a minimal set of `Stream`s likely to be useful in a reactive setting. You can find them at [lib/utils](lib/utils).

## <a name='`computationcache`'></a>`ComputationCache`

You can find yourself in a situtation where you want to create parameterized computations. The naive way is to create a new computation each time, but this results in duplicated computation if multiple computations with the same parameters are created. For such cases, you can use `ComputationCache` to "unify" computations with identical parameters. `ComputationCache` makes sure each cache key has at most one active computation at any point in time, no matter how many computations for that key have been created. Of course, it preserves the reactive semantics by notifying the listeners and downstream computations of all the created computations whenever necessary.

## <a name='advanced-usage'></a>Advanced usage

This section describes advanced capabilities of Computed. You should seldom need them.

### <a name='using-computations-opportunistically'></a>Using computations opportunistically

You may find yourself in a situation where there are multiple ways to compute a value, where one way is expensive but computes several related values, and the other is computationally cheaper but more focused. In such cases, you can use `useWeak`. It allows computations to reactively use other computations without triggering them to be computed if they have no listeners or non-weak downstream computations.

Calling `.useWeak` on a computation weakly subscribes the current computation to it. If the target computation has listeners or non-weak downstream, `useWeak` will return its value. Otherwise, it will throw a `NoStrongUserException`. It will schedule the current computation to be re-run if the target computation changes value or loses all of its listeners or non-weak downstream, but not if it gains either.

### <a name='customizing-downstream'></a>Customizing downstream

By default, Computed schedules downstream computations to be re-run whenever a computation changes value. If this is not computationally efficient, you can customize the downstream which should be schedule for being rerun. You can find an example in the [`computed_collections` repo](https://github.com/mstniy/computed.dart/blob/master/packages/computed_collections/lib/src/utils/custom_downstream.dart).

Note that using this feature requires you to depend on the Computed internals, restricting you to individual patch releases. Use it with great care, as Computed has no guardrails against breaking reactive consistency if you use custom downstreams.

## <a name='faq'></a>FAQ

- Q: Why am I getting `Computed expressions must be purely functional. Please use listeners for side effects.`
- A: On debug mode, Computed runs the given computations twice and checks if both calls return the same value. If this does not hold, it throws this assertion. Possible reasons include mutating and using a mutable value inside the computation or returning a type which does not implement deep comparisons, like `List` or `Set`. Consider returning a type which does implement value semantics for its equality operator, or using [`assertIdempotent: false`](#`assertidempotent`). If your computation kickstarts an async process and returns a `Stream` or `Future`, consider using `Computed.async` as described in [computed queries](#computed-queries).

## <a name='pitfalls'></a>Pitfalls

### <a name='do-not-use-mutable-values-in-computations'></a>Do not use mutable values in computations

Especially if conditionals depending on them are guarding `.use` expressions. Here is an example:

```dart
Stream<int> value;
var b = false;

final c = $(() => b ? value.use : 42);
```

As this may cause Computed to stop tracking `value`, breaking the reactivity of the computation.

### <a name='use-the-async-mode-for-computations-kicking-off-async-operations'></a>Use the async mode for computations kicking off async operations

This will disable some checks which don't make sense for such computations.

### <a name='do-not-`.use`-a-`future`s-or-`stream`-inside-the-computation-that-created-it'></a>Do not `.use` a `Future`s or `Stream` inside the computation that created it

As this might lead to an infinite loop between the computation running, creating a new data source, and running again when it produces a value.

### <a name='do-not-`.use`-a-computation-inside-the-computation-that-created-it'></a>Do not `.use` a computation inside the computation that created it

As this might be inefficient if the outer computation re-creates the inner computation each time. Instead, consider creating the inner computation before the outer computation, and capturing it as part of its closure. If you require reactive values to construct the inner computation, consider constructing it in a dedicated middle computation with `assertIdempotent: false` and `.unwrap`ing the middle computation inside the outer one.

### <a name='`future`s-returned-from-computations-are-not-awaited'></a>`Future`s returned from computations are not awaited

At least for memoization purposes. The DAG pass never awaits, even if a computation returns a `Future`. The results are passed as-is to downstream computations. If you want to instead return the values produced by the asynchronous operations returned by a computation, see `.unwrap`.

### <a name='do-not-forget-to-`.use`-or-`.react`-your-data-sources'></a>Do not forget to `.use` or `.react` your data sources

If a computation returns without calling either of these on a data source, Computed assumes it doesn't depend on it.

### <a name='keep-in-mind-that-`.prev`-does-not-subscribe'></a>Keep in mind that `.prev` does not subscribe

It is also "subjective" to the running computation. Different functions can have different `.prev`s on the same data source or computation.

### <a name='`.react`-is-not-`.listen`'></a>`.react` is not `.listen`

`.react` can only be used inside computations, `.listen` can only be used outside computations.  
`.react` callbacks must not have side effects beyond the local scope of the current computation. `.listen` callbacks are where side effects are supposed to happen.  
`.listen` keeps a reference to the given callback and calls it at a later point in time. `.react` either calls the given function before returning or doesn't call it at all.
