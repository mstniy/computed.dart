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
