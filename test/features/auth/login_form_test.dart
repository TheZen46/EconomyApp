import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/auth/presentation/providers/auth_provider.dart';
import 'package:t_aidy/features/auth/presentation/widgets/login_form.dart';

class MockAuthNotifier extends StateNotifier<AuthState> implements AuthNotifier {
  MockAuthNotifier([super.state = const AuthState()]);

  bool signInWithEmailPasswordCalled = false;
  bool signUpCalled = false;
  bool resetPasswordCalled = false;

  String? capturedEmail;
  String? capturedPassword;

  @override
  Future<void> signIn({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    signInWithEmailPasswordCalled = true;
    capturedEmail = email;
    capturedPassword = password;
  }

  @override
  Future<void> signInWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    signInWithEmailPasswordCalled = true;
    capturedEmail = email;
    capturedPassword = password;
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    signUpCalled = true;
    capturedEmail = email;
    capturedPassword = password;
  }

  @override
  Future<void> signOut() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  @override
  Future<void> resetPassword(String email) async {
    resetPasswordCalled = true;
    capturedEmail = email;
  }

  @override
  Future<void> signInWithGoogle({bool rememberMe = true}) async {}

  @override
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('LoginForm Widget Unit Tests', () {
    late MockAuthNotifier mockNotifier;

    setUp(() {
      mockNotifier = MockAuthNotifier();
    });

    Widget createTestWidget({MockAuthNotifier? notifier}) {
      return ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => notifier ?? mockNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LoginForm(),
            ),
          ),
        ),
      );
    }

    testWidgets('rejects invalid email formats per RFC 5322 regex', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final emailField = find.widgetWithText(TextFormField, 'Email');
      final submitButton = find.widgetWithText(ElevatedButton, 'Sign In');

      final invalidEmails = [
        'plainaddress',
        '@missingusername.com',
        'username@.com',
        'username@domain..com',
        'username@domain',
      ];

      for (final email in invalidEmails) {
        await tester.enterText(emailField, email);
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(find.text('Enter a valid email address'), findsOneWidget);
        expect(mockNotifier.signInWithEmailPasswordCalled, isFalse);
      }
    });

    testWidgets('rejects passwords failing complexity rules (min 8, 1 number, 1 special)', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final emailField = find.widgetWithText(TextFormField, 'Email');
      final passwordField = find.widgetWithText(TextFormField, 'Password');
      final submitButton = find.widgetWithText(ElevatedButton, 'Sign In');

      await tester.enterText(emailField, 'valid@example.com');

      // Less than 8 characters
      await tester.enterText(passwordField, 'P1@a');
      await tester.tap(submitButton);
      await tester.pumpAndSettle();
      expect(find.text('Password must be at least 8 characters'), findsOneWidget);

      // No number
      await tester.enterText(passwordField, 'PasswordWithoutNum!');
      await tester.tap(submitButton);
      await tester.pumpAndSettle();
      expect(find.text('Password must contain at least 1 number'), findsOneWidget);

      // No special character
      await tester.enterText(passwordField, 'PasswordWithNum123');
      await tester.tap(submitButton);
      await tester.pumpAndSettle();
      expect(find.text('Password must contain at least 1 special character'), findsOneWidget);
    });

    testWidgets('successfully triggers signInWithEmailPassword on valid credentials', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final emailField = find.widgetWithText(TextFormField, 'Email');
      final passwordField = find.widgetWithText(TextFormField, 'Password');
      final submitButton = find.widgetWithText(ElevatedButton, 'Sign In');

      await tester.enterText(emailField, 'valid.user+1@example.com');
      await tester.enterText(passwordField, 'StrongP@ssw0rd!');
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(mockNotifier.signInWithEmailPasswordCalled, isTrue);
      expect(mockNotifier.capturedEmail, 'valid.user+1@example.com');
      expect(mockNotifier.capturedPassword, 'StrongP@ssw0rd!');
    });

    testWidgets('toggles password obscuring when tapping visibility icon', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final toggleButton = find.byIcon(Icons.visibility_off_outlined);
      expect(toggleButton, findsOneWidget);

      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });
}
