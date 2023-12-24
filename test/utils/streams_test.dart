import 'package:computed/utils/streams.dart';
import 'package:test/test.dart';

void main() {
  group('ValueStream', () {
    test('values are not buffered', () async {
      final s = ValueStream(sync: true);
      s.add(0);
      s.add(1);

      var lCnt = 0;
      int? lastEvent;

      s.listen((event) {
        lCnt++;
        lastEvent = event;
      }, onError: (e) => fail(e.toString()));

      for (var i = 0; i < 2; i++) {
        await Future.value(); // Just in case
      }

      expect(lCnt, 1);
      expect(lastEvent, 1);
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
  });

  group('ResourceStream', () {
    test('respects create/dispose', () async {
      var cCnt = 0;
      int create() {
        return cCnt++;
      }

      var dCnt = 0;
      int? lastDispose;
      void dispose(int i) {
        dCnt++;
        lastDispose = i;
      }

      var lCnt = 0;
      int? lastEvent;
      void listener(e) {
        lCnt++;
        lastEvent = e;
      }

      final s = ResourceStream(create, dispose, sync: true);
      expect(cCnt, 0);
      var sub = s.listen(listener, onError: (e) => fail(e.toString()));
      await Future.value();
      expect(cCnt, 1);
      expect(dCnt, 0);
      expect(lCnt, 1);
      expect(lastEvent, 0);
      sub.cancel();
      expect(cCnt, 1);
      expect(dCnt, 1);
      expect(lastDispose, 0);
      expect(lCnt, 1);
      sub = s.listen(listener, onError: (e) => fail(e.toString()));
      await Future.value();
      expect(cCnt, 2);
      expect(dCnt, 1);
      expect(lCnt, 2);
      expect(lastEvent, 1);
      s.add(42);
      expect(cCnt, 2);
      expect(dCnt, 2);
      expect(lCnt, 3);
      expect(lastDispose, 1);
      sub.cancel();
      expect(cCnt, 2);
      expect(dCnt, 3);
      expect(lCnt, 3);
      expect(lastDispose, 42);
    });
    test('propagates exceptions thrown by create', () async {
      var cCnt = 0;
      int? createReturn;
      int createThrow = 42;
      int create() {
        cCnt++;
        if (createReturn != null) {
          return createReturn;
        } else {
          throw createThrow;
        }
      }

      var dCnt = 0;
      int? lastDispose;
      void dispose(int i) {
        dCnt++;
        lastDispose = i;
      }

      var lCnt = 0;
      int? lastEvent;
      void listener(e) {
        lCnt++;
        lastEvent = e;
      }

      var eCnt = 0;
      int? lastErr;
      void errorListener(e) {
        eCnt++;
        lastErr = e;
      }

      final s = ResourceStream(create, dispose, sync: true);
      expect(cCnt, 0);
      var sub = s.listen(listener, onError: errorListener);
      await Future.value();
      expect(cCnt, 1);
      expect(dCnt, 0);
      expect(lCnt, 0);
      expect(eCnt, 1);
      expect(lastErr, 42);
      s.add(0);
      expect(cCnt, 1);
      expect(dCnt, 0);
      expect(lCnt, 1);
      expect(eCnt, 1);
      expect(lastEvent, 0);
      sub.cancel();
      await Future.value();
      expect(cCnt, 1);
      expect(dCnt, 1);
      expect(lCnt, 1);
      expect(eCnt, 1);
      expect(lastDispose, 0);

      s.addError(1);
      createReturn = 2;
      sub = s.listen(listener, onError: errorListener);
      await Future.value();
      expect(cCnt, 2);
      expect(dCnt, 1);
      expect(lCnt, 2);
      expect(eCnt, 1);
      expect(lastEvent, 2);

      s.addError(3);
      expect(cCnt, 2);
      expect(dCnt, 2);
      expect(lCnt, 2);
      expect(eCnt, 2);
      expect(lastDispose, 2);
      expect(lastErr, 3);

      sub.cancel();
      expect(cCnt, 2);
      expect(dCnt, 2);
      expect(lCnt, 2);
      expect(eCnt, 2);

      s.add(3);
      sub = s.listen(listener, onError: errorListener);
      await Future.value();
      expect(cCnt, 2);
      expect(dCnt, 2);
      expect(lCnt, 3);
      expect(eCnt, 2);
      expect(lastEvent, 3);

      sub.cancel();
      expect(cCnt, 2);
      expect(dCnt, 3);
      expect(lCnt, 3);
      expect(eCnt, 2);
      expect(lastDispose, 3);
    });
  });
}
