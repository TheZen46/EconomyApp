import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:t_aidy/core/services/biometric_service.dart';
import 'package:t_aidy/features/auth/presentation/widgets/biometric_guard.dart';

class MockBiometricLocalAuth implements LocalAuthentication {
  bool canCheck = true;
  bool isSupported = true;
  bool authSuccess = true;
  int authAttempts = 0;

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
    authAttempts++;
    return authSuccess;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestBiometricNotifier extends BiometricEnabledNotifier {
  TestBiometricNotifier(bool initial) : super(null) {
    state = initial;
  }
}

void main() {
  group('BiometricGuard Widget Tests', () {
    late MockBiometricLocalAuth mockAuth;

    setUp(() {
      mockAuth = MockBiometricLocalAuth();
    });

    testWidgets('renders child directly when biometric lock is disabled', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricEnabledProvider.overrideWith((ref) => TestBiometricNotifier(false)),
            biometricServiceProvider.overrideWithValue(BiometricService(localAuth: mockAuth)),
          ],
          child: const MaterialApp(
            home: BiometricGuard(
              child: Text('Secret Financial Dashboard'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Secret Financial Dashboard'), findsOneWidget);
      expect(find.text('tAIdy Locked'), findsNothing);
    });

    testWidgets('displays lock screen when biometric lock is enabled and authentication fails', (tester) async {
      mockAuth.authSuccess = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricEnabledProvider.overrideWith((ref) => TestBiometricNotifier(true)),
            biometricServiceProvider.overrideWithValue(BiometricService(localAuth: mockAuth)),
          ],
          child: const MaterialApp(
            home: BiometricGuard(
              child: Text('Secret Financial Dashboard'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Screen is locked, content masked
      expect(find.text('Secret Financial Dashboard'), findsNothing);
      expect(find.text('tAIdy Locked'), findsOneWidget);
      expect(find.text('Unlock with Biometrics'), findsOneWidget);
      expect(find.text('Biometric authentication canceled or failed. Please try again.'), findsOneWidget);
    });

    testWidgets('unlocks content when tapping Unlock with Biometrics after prior failure', (tester) async {
      mockAuth.authSuccess = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricEnabledProvider.overrideWith((ref) => TestBiometricNotifier(true)),
            biometricServiceProvider.overrideWithValue(BiometricService(localAuth: mockAuth)),
          ],
          child: const MaterialApp(
            home: BiometricGuard(
              child: Text('Secret Financial Dashboard'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('tAIdy Locked'), findsOneWidget);

      // User retries with successful auth
      mockAuth.authSuccess = true;
      await tester.tap(find.text('Unlock with Biometrics'));
      await tester.pumpAndSettle();

      // Now unlocked
      expect(find.text('Secret Financial Dashboard'), findsOneWidget);
      expect(find.text('tAIdy Locked'), findsNothing);
    });

    testWidgets('locks screen on AppLifecycleState.paused and re-prompts on resumed', (tester) async {
      mockAuth.authSuccess = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricEnabledProvider.overrideWith((ref) => TestBiometricNotifier(true)),
            biometricServiceProvider.overrideWithValue(BiometricService(localAuth: mockAuth)),
          ],
          child: const MaterialApp(
            home: BiometricGuard(
              child: Text('Secret Financial Dashboard'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Secret Financial Dashboard'), findsOneWidget);

      // App goes to background (paused)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      // Next auth attempt on resume fails
      mockAuth.authSuccess = false;

      // App resumes
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Screen is locked on resume because biometric auth failed
      expect(find.text('tAIdy Locked'), findsOneWidget);
      expect(find.text('Secret Financial Dashboard'), findsNothing);

      // User retries and succeeds
      mockAuth.authSuccess = true;
      await tester.tap(find.text('Unlock with Biometrics'));
      await tester.pumpAndSettle();

      // Now unlocked
      expect(find.text('Secret Financial Dashboard'), findsOneWidget);
      expect(find.text('tAIdy Locked'), findsNothing);
    });
  });
}
