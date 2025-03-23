## 0.1.2 - 2025-03-23

- `SnapshotStream`: Fix a bug where additions/deletions of keys with null values were not reflected properly in the change stream

## 0.1.1 - 2024-10-09

- `.flat`: Fixed a bug where subscribing only to `.changes` was broken
- `CSTracker`: Iterate over key/value streams instead of key changes if there are fewer of them
- Added `.fromChangeStreamWithPrev`, `.fromPiecewise` and `.fromPiecewiseComputed`

## 0.1.0 - 2024-09-16

Initial release
