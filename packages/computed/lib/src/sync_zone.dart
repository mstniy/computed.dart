import 'dart:async';

import '../computed.dart';

/// A zone that disallows most async operations.
///
/// Note that it does not need to override [Zone.handleUncaughtError],
/// as it does not allow registering callbacks in the first place.
/// Likewise, it does not need to override [Zone.scheduleMicrotask].
final computedZone = ZoneSpecification(
  createPeriodicTimer: (self, parent, zone, period, f) =>
      throw ComputedAsyncError(),
  createTimer: (self, parent, zone, duration, f) => throw ComputedAsyncError(),
  errorCallback: (self, parent, zone, error, stackTrace) =>
      throw ComputedAsyncError(),
  fork: (self, parent, zone, specification, zoneValues) =>
      throw ComputedAsyncError(),
  registerBinaryCallback: <R, T1, T2>(self, parent, zone, f) {
    throw ComputedAsyncError();
  },
  registerCallback: <R>(self, parent, zone, f) {
    throw ComputedAsyncError();
  },
  registerUnaryCallback: <R, T>(self, parent, zone, f) {
    throw ComputedAsyncError();
  },
);
