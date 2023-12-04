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
- [FAQ](#FAQ)
- [Pitfalls](#Pitfalls)
  - [Do not use mutable values in computations](#Donotusemutablevaluesincomputations)
  - [Do not create new `Future`s inside computations](#DonotcreatenewFuturesinsidecomputations)
  - [Do not forget to `.use` or `.react` your data sources](#Donotforgetto.useor.reactyourdatasources)
  - [Keep in mind that `.prev` does not subscribe](#Keepinmindthat.prevdoesnotsubscribe)
  - [`.react` is not `.listen`](#.reactisnot.listen)

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
final c = Computed(() {
    s.use; // Make sure it has a value
    late int res;
    s.react((val) => res = val - s.prevOr(0));
    return res;
});
```

`.prevOr` is a handy shortcut which returns the given fallback value instead of throwing `NoValueException` if the data source had no value the last time the current computation changed value.

Note that the listeners of this computations or other computations using the result of this computation will not be notified if the difference does not change, as computation results are memoized. If this behaviour is not suitable for your application logic, you can return a counter along with the value itself.

You can also create temporal accumulators:

```
final sum = Computed<int>.withPrev((prev) {
    var res = prev;
    s.react((val) => res += val);
    return res;
}, initialPrev: 0);
```

Note the use of `.react` instead of `.use` in these examples.
`.react` marks the current computation to be recomputed for all values produced by a data source, even if it consecutively produces a pair of values comparing `==`. `.react` will run the given function if the data source has produced a new value/error. As a rule of thumb, you should use `.react` over `.use` for data sources representing a sequence of events rather than a state.

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

### <a name='DonotcreatenewFuturesinsidecomputations'></a>Do not create new `Future`s inside computations

This will lead to an infinite loop, assuming you `.use` them afterwards, as each run of the computation will produce a new `Future`.

### <a name='Donotforgetto.useor.reactyourdatasources'></a>Do not forget to `.use` or `.react` your data sources

If a computation returns without calling either of these on a data source, Computed assumes it doesn't depend on it.

### <a name='Keepinmindthat.prevdoesnotsubscribe'></a>Keep in mind that `.prev` does not subscribe

It is also "subjective" to the running computation. Different functions can have different `.prev`s on the same data source or computation.

### <a name='.reactisnot.listen'></a>`.react` is not `.listen`

`.react` can only be used inside computations, `.listen` can only be used outside computations.  
`.react` callbacks must not have side effects. `.listen` callbacks are where side effects are supposed to happen.  
`.listen` keeps a reference to the given callback and calls it at a later point in time. `.react` either calls the given function before returning or doesn't call it at all.
