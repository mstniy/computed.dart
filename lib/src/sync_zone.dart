import 'dart:async';

import 'package:computed/computed.dart';

final computedZone = ZoneSpecification(
  createPeriodicTimer: (self, parent, zone, period, f) =>
      throw ComputedAsyncError(),
  createTimer: (self, parent, zone, duration, f) => throw ComputedAsyncError(),
  errorCallback: (self, parent, zone, error, stackTrace) =>
      throw ComputedAsyncError(),
  fork: (self, parent, zone, specification, zoneValues) =>
      throw ComputedAsyncError(),
  handleUncaughtError: (self, parent, zone, error, stackTrace) =>
      throw ComputedAsyncError(),
  registerBinaryCallback: <R, T1, T2>(self, parent, zone, f) =>
      throw ComputedAsyncError(),
  registerCallback: <R>(self, parent, zone, f) => throw ComputedAsyncError(),
  registerUnaryCallback: <R, T>(self, parent, zone, f) =>
      throw ComputedAsyncError(),
  scheduleMicrotask: (self, parent, zone, f) => throw ComputedAsyncError(),
);
