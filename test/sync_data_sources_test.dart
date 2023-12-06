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

  void react(void Function(T) onData, [void Function(Object)? onError]) {
    final caller = GlobalCtx.currentComputation;
    caller.dataSourceReact<T>(
        this,
        () => this.use,
        (router) => _TestDataSourceSubscription(
            this, () => router.onDataSourceData(value)),
        true,
        value,
        onData,
        onError);
  }

  T get prev {
    final caller = GlobalCtx.currentComputation;
    return caller.dataSourcePrev(this);
  }
}

void main() {
  group('sync data sources', () {
    test('work', () async {
      final s = _TestDataSource(1);
      int? prevExpectation; // If null, expect NVE
      final c = Computed(() {
        try {
          expect(s.prev, prevExpectation);
        } on NoValueException {
          expect(prevExpectation, null);
        }
        return s.use + s.use;
      });

      var expectation = 2;
      var subCnt = 0;

      final sub = c.listen((event) {
        subCnt++;
        expect(event, expectation);
      }, (e) => fail(e.toString()));

      expect(subCnt, 0);
      await Future.value();
      expect(subCnt, 1);
      prevExpectation = 1;
      expectation = 4;
      s.value = 2;
      expect(subCnt, 2);

      sub.cancel();
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

      expect(subCnt, 0);
      await Future.value();
      expect(subCnt, 1);
      expectation = 2;
      s.value = 1;
      expect(subCnt, 2);

      sub.cancel();
    });

    test('can use react', () async {
      final s = _TestDataSource(0);
      int? prevExpectation; // If null, expect NVE
      final c = Computed(() {
        try {
          expect(s.prev, prevExpectation);
        } on NoValueException {
          expect(prevExpectation, null);
        }
        late int res;
        s.react((p0) => res = p0);
        return res;
      }, memoized: false);

      var expectation = 0;
      var subCnt = 0;

      final sub = c.listen((event) {
        subCnt++;
        expect(event, expectation);
      }, (e) => fail(e.toString()));

      expect(subCnt, 0);
      await Future.value();
      expect(subCnt, 1);
      prevExpectation = 0;
      expectation = 1;
      s.value = 1;
      expect(subCnt, 2);

      sub.cancel();
    });
  });
}
