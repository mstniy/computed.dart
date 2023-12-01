import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/src/computed.dart';
import 'package:computed/src/data_source_subscription.dart';
import 'package:test/test.dart';

class _TestDataSourceSubscription<T> implements DataSourceSubscription<T> {
  final _TestDataSource<T> _s;
  final void Function() _onData;

  _TestDataSourceSubscription(this._s, this._onData) {
    _s.addListener(_onData);
  }

  @override
  Future<void> cancel() {
    _s.removeListener(_onData);
    return Future.value();
  }
}

class _TestDataSource<T> {
  T _value;
  final _listeners = <void Function()>{};

  _TestDataSource(this._value);

  T get value => _value;
  set value(T newValue) {
    _value = newValue;
    for (var l in _listeners) {
      l();
    }
  }

  void addListener(void Function() l) {
    _listeners.add(l);
  }

  void removeListener(void Function() l) {
    _listeners.remove(l);
  }
}

extension _TestDataSourceComputedExtension<T> on _TestDataSource<T> {
  T get use {
    final caller = GlobalCtx.currentComputation;
    return caller.dataSourceUse(
        this,
        () => this.use,
        (router) => _TestDataSourceSubscription(
            this, () => router.onDataSourceData(value)),
        true,
        value);
  }
}

void main() {
  group('sync data sources', () {
    // TODO: Also test react
    test('work', () async {
      final s = _TestDataSource(1);
      final c = Computed(() => s.use + s.use);

      var expectation = 2;
      var subCnt = 0;

      final sub = c.listen((event) {
        subCnt++;
        expect(event, expectation);
      }, (e) => fail(e.toString()));

      try {
        expect(subCnt, 0);
        await Future.value();
        expect(subCnt, 1);
        expectation = 4;
        s.value = 2;
        expect(subCnt, 2);
      } finally {
        sub.cancel();
      }
    });

    test('can have null value', () async {
      final s = _TestDataSource<int?>(null);
      final c = Computed(() => (s.use ?? 42) + (s.use ?? 42));

      var expectation = 84;
      var subCnt = 0;

      final sub = c.listen((event) {
        subCnt++;
        expect(event, expectation);
      }, (e) => fail(e.toString()));

      try {
        expect(subCnt, 0);
        await Future.value();
        expect(subCnt, 1);
        expectation = 2;
        s.value = 1;
        expect(subCnt, 2);
      } finally {
        sub.cancel();
      }
    });
  });
}
