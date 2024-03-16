import 'package:computed/utils/streams.dart';
import 'package:test/test.dart';

void main() {
  group('ValueStream', () {
    test('values produced while not being listened are not buffered', () async {
      final s = ValueStream(sync: true);
      s.add(0);
      s.add(1);

      var lCnt = 0;
      int? lastEvent;

      s.listen((event) {
        lCnt++;
        lastEvent = event;
      }, onError: (e) => fail(e.toString()));

      expect(lCnt, 0);

      await Future.value();

      expect(lCnt, 1);
      expect(lastEvent, 1);

      await Future.value();

      expect(lCnt, 1);
    });

    test('values produced in the same microtask are not buffered', () async {
      final s = ValueStream();

      var lCnt = 0;
      int? lastEvent;

      var eCnt = 0;
      int? lastError;

      s.listen((event) {
        lCnt++;
        lastEvent = event;
      }, onError: (e) {
        eCnt++;
        lastError = e;
      });

      expect(lCnt, 0);

      s.add(0);
      s.add(1);

      expect(lCnt, 0);

      await Future.value();

      expect(lCnt, 1);
      expect(lastEvent, 1);

      await Future.value();

      expect(lCnt, 1);
      expect(eCnt, 0);

      s.addError(0);
      s.addError(1);

      expect(lCnt, 1);
      expect(eCnt, 0);

      await Future.value();

      expect(lCnt, 1);
      expect(eCnt, 1);
      expect(lastError, 1);

      await Future.value();

      expect(lCnt, 1);
      expect(eCnt, 1);
    });

    test('dedups equal values', () async {
      final s = ValueStream(sync: true);

      var lCnt = 0;
      int? lastEvent;

      var eCnt = 0;
      int? lastError;

      s.listen((event) {
        lCnt++;
        lastEvent = event;
      }, onError: (err) {
        eCnt++;
        lastError = err;
      });

      s.add(0);
      expect(lCnt, 1);
      expect(lastEvent, 0);
      s.add(0);
      expect(lCnt, 1);
      s.add(1);
      expect(lCnt, 2);
      expect(lastEvent, 1);
      expect(eCnt, 0);
      s.addError(1);
      expect(eCnt, 1);
      expect(lCnt, 2);
      expect(lastError, 1);
      s.addError(1);
      expect(eCnt, 2);
      expect(lCnt, 2);
      expect(lastError, 1);
      s.add(1);
      expect(eCnt, 2);
      expect(lCnt, 3);
      expect(lastEvent, 1);
    });

    test('can add values after attaching listeners', () async {
      final s = ValueStream(sync: true);

      var lCnt = 0;
      int? lastEvent;

      s.listen((event) {
        lCnt++;
        lastEvent = event;
      }, onError: (e) => fail(e.toString()));

      s.add(0);

      expect(lCnt, 1);
      expect(lastEvent, 0);
    });

    test('can add errors', () async {
      final s = ValueStream(sync: true);

      var lCnt = 0;
      int? lastEvent;

      s.listen((e) => fail('Must not produce value'), onError: (event) {
        lCnt++;
        lastEvent = event;
      });

      s.addError(0);

      expect(lCnt, 1);
      expect(lastEvent, 0);
    });

    test('can re-listen after cancel', () async {
      var lCnt = 0;
      int? lastEvent;

      void listener(event) {
        lCnt++;
        lastEvent = event;
      }

      var errCnt = 0;
      int? lastError;

      void errorListener(error) {
        errCnt++;
        lastError = error;
      }

      final s = ValueStream(sync: true);

      var sub = s.listen(listener, onError: (e) => fail(e.toString()));

      s.add(0);

      expect(lCnt, 1);
      expect(lastEvent, 0);

      // Also test the case where the last added was an error

      sub.cancel();

      sub = s.listen(listener, onError: errorListener);
      await Future.value();
      expect(lCnt, 2);
      expect(lastEvent, 0);

      expect(errCnt, 0);

      s.addError(1);
      expect(lCnt, 2);
      expect(errCnt, 1);
      expect(lastError, 1);

      sub.cancel();

      s.listen(listener, onError: errorListener);
      await Future.value();

      expect(lCnt, 2);
      expect(errCnt, 2);
      expect(lastError, 1);
    });

    test('onListen and onCancel works', () {
      var olCnt = 0;
      var ocCnt = 0;
      final s = ValueStream(
          onListen: () => olCnt++, onCancel: () => ocCnt++, sync: true);

      expect(olCnt, 0);
      expect(ocCnt, 0);

      final sub = s.listen((event) => fail('Must not produce any value'),
          onError: (e) => fail(e.toString()));

      expect(olCnt, 1);
      expect(ocCnt, 0);

      sub.cancel();

      expect(olCnt, 1);
      expect(ocCnt, 1);
    });

    test('is not broadcast', () {
      final s = ValueStream();
      s.listen((event) {});
      try {
        s.listen((event) {});
        fail("Must have thrown");
      } catch (e) {
        expect(e, isA<StateError>());
        expect(
            (e as StateError).message, 'Stream has already been listened to.');
      }
    });

    test('seeded works', () async {
      final s = ValueStream.seeded(0);

      var lCnt = 0;
      int? lastEvent;

      s.listen((event) {
        lCnt++;
        lastEvent = event;
      }, onError: (e) => fail(e.toString()));

      await Future.value();

      expect(lCnt, 1);
      expect(lastEvent, 0);

      await Future.value();

      expect(lCnt, 1);
    });
  });
}
