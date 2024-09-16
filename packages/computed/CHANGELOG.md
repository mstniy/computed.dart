## 0.5.0 - 2024-09-16

- New computation configuration options: `dispose`, `onCancel`, `assertIdempotent`
- `useWeak`
- Revamped the DAG runner. Lazily discovers the relevant part of the computation graph. Supports custom downstreams.
- Changed `.prev` semantics
- Removed mocking support
- Removed `ResourceStream` in favor of disposing async computations
- `ComputationCache`
- `ValueStream` now implements the `EventSink` interface.
- If a memoized computation's result is equal to the previous one, keep using the old one
- Support receiving stack traces from data sources
- `.listen`: Made `onError` optional
- `.listen`: `onError` can take the stacktrace as a parameter
- Allow listeners to cancel themselves and other listeners on the same computation
- `ValueStream`: `hasListener`
- `ValueStream`: `add`/`addError`: Avoid scheduling a microtask if there are no listeners
- Fix a bug where sync exceptions thrown while attempting to listen to data sources corrupted the internal state

## 0.4.1 - 2023-12-26

- `ValueStream`: Support initial values

## 0.4.0 - 2023-12-25

- Added effects: A simpler way to express side effects using multiple data sources/computations
- Async mode for computations starting async operations
- `.unwrap` to make computed async operations easier to use
- Stream utils: `ValueStream` and `ResourceStream`
- Cycle detection: Walk the dag explicitly instead of recomputing the upstream
- Unset `_currentComputation` before notifying listeners
- Subclass-customizable behaviour for when a computation's dependency has changed
- Trigger the current Zone's `handleUncaughtError` if a computation which has listeners throws but none of the listeners have an error handler

## 0.3.2 - 2023-12-21

- Allow computations to use other computations via `.asStream`
- Added `useOr`

## 0.3.1 - 2023-12-17

- Disallow computations from doing most async operations
- Bugfix for non-memoized computations
- Avoid modifying internal state in asserts
- Move `_reacting` to the global context to save memory

## 0.3.0 - 2023-12-11

- Removed `.useAll`, replace with `.react`.
- Introduced non-memoized computations.
- Removed `.withSelf`, replaced with `.withPrev`.
- Introduced `prevOr`: Returns a given fallback value instead of throwing `NoValueException`.
- Bugfixes
- Introduced a shorthand dollar notation for defining computed values.
- Allow data source initial values to be specified as functionals.

## 0.2.2 - 2023-11-28

- Improve dependencies

## 0.2.1 - 2023-11-27

- Loosen semver bound on test
- Fix README

## 0.2.0 - 2023-11-26

- `.useAll` for streams: Disables memoization
- Ability to mock emit events from data sources directly
- Memoize exceptions as well
- Allow computations to re-run even with upstream nodes without values
- `asStream`: Use a `StreamController`
- Added `asBroadcastStream`: Uses a `StreamController.broadcast`
- Native public listen method
- Assert if the computation returns a value on the first run but throws on the second

## 0.1.0 - 2023-11-21

- Added testing utilities: `fix`, `fixException`, `mock` and `unmock`.
- Detect cyclic `.use`s.
- Added `.prev` to get the previous value of a data source.
- Assert that running computations a second time returns the same result as the first to try to detect side effects.
- Computations now unsubscribe from abandoned dependencies.
- Allow data sources to pass errors to computations.
- Defined a public API for listeners.

## 0.0.1 - 2023-11-15

- Initial version
