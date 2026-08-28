import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:t_aidy/core/services/biometric_service.dart';

class FakeLocalAuthentication implements LocalAuthentication {
  bool canCheck = true;
  bool isSupported = true;
  bool authResult = true;
  String? lastReason;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<bool> isDeviceSupported() async => isSupported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    lastReason = localizedReason;
    return authResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('BiometricService Tests', () {
    late FakeLocalAuthentication fakeAuth;
    late BiometricService service;

    setUp(() {
      fakeAuth = FakeLocalAuthentication();
      service = BiometricService(localAuth: fakeAuth);
    });

    test('canAuthenticate returns true when device supports biometrics', () async {
      fakeAuth.canCheck = true;
      fakeAuth.isSupported = true;
      expect(await service.canAuthenticate(), isTrue);
    });

    test('canAuthenticate returns false when neither check nor support is available', () async {
      fakeAuth.canCheck = false;
      fakeAuth.isSupported = false;
      expect(await service.canAuthenticate(), isFalse);
    });

    test('authenticate passes localized reason and returns success', () async {
      fakeAuth.authResult = true;
      final result = await service.authenticate('Test Reason');
      expect(result, isTrue);
      expect(fakeAuth.lastReason, 'Test Reason');
    });

    test('authenticate returns false when authentication fails', () async {
      fakeAuth.authResult = false;
      final result = await service.authenticate('Test Reason');
      expect(result, isFalse);
    });
  });
}
