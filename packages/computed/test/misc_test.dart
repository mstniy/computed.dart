import 'package:computed/computed.dart';
import 'package:test/test.dart';

void main() {
  group('NoValueException', () {
    test('operator== works', () {
      expect(NoValueException(), NoValueException());
      expect(NoValueException(), isNot(NoStrongUserException()));
      expect(NoValueException(), isNot(0));
    });

    test('hashCode works', () {
      expect(NoValueException().hashCode, NoValueException().hashCode);
      expect(
          NoValueException().hashCode, isNot(NoStrongUserException().hashCode));
    });
  });

  group('NoStrongUserException', () {
    test('operator== works', () {
      expect(NoStrongUserException(), NoStrongUserException());
      expect(NoStrongUserException(), isNot(NoValueException()));
      expect(NoStrongUserException(), isNot(0));
    });

    test('hashCode works', () {
      expect(
          NoStrongUserException().hashCode, NoStrongUserException().hashCode);
      expect(
          NoStrongUserException().hashCode, isNot(NoValueException().hashCode));
    });
  });

  group('CyclicUseException', () {
    test('operator== works', () {
      expect(CyclicUseException(), CyclicUseException());
      expect(CyclicUseException(), isNot(NoValueException()));
      expect(CyclicUseException(), isNot(0));
    });

    test('hashCode works', () {
      expect(CyclicUseException().hashCode, CyclicUseException().hashCode);
      expect(CyclicUseException().hashCode, isNot(NoValueException().hashCode));
    });
  });

  group('ComputedAsyncError', () {
    test('operator== works', () {
      expect(ComputedAsyncError(), ComputedAsyncError());
      expect(ComputedAsyncError(), isNot(NoValueException()));
      expect(ComputedAsyncError(), isNot(0));
    });

    test('hashCode works', () {
      expect(ComputedAsyncError().hashCode, ComputedAsyncError().hashCode);
      expect(ComputedAsyncError().hashCode, isNot(NoValueException().hashCode));
    });
  });
}
