import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/auth/presentation/pages/login_page.dart';
import 'package:t_aidy/features/auth/presentation/providers/auth_provider.dart';

class FakeAuthNotifier extends StateNotifier<AuthState> implements AuthNotifier {
  FakeAuthNotifier([super.state = const AuthState()]);

  bool signInCalled = false;
  bool signUpCalled = false;
  bool resetPasswordCalled = false;
  bool clearErrorCalled = false;

  String? lastEmail;
  String? lastPassword;

  @override
  Future<void> signIn({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    signInCalled = true;
    lastEmail = email;
    lastPassword = password;
  }

  @override
  Future<void> signInWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    signInCalled = true;
    lastEmail = email;
    lastPassword = password;
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    signUpCalled = true;
    lastEmail = email;
    lastPassword = password;
  }

  @override
  Future<void> signOut() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  @override
  Future<void> resetPassword(String email) async {
    resetPasswordCalled = true;
    lastEmail = email;
  }

  @override
  Future<void> signInWithGoogle({bool rememberMe = true}) async {}

  @override
  void clearError() {
    clearErrorCalled = true;
    state = state.copyWith(errorMessage: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeAuthNotifier fakeAuthNotifier;

  setUp(() {
    fakeAuthNotifier = FakeAuthNotifier();
  });

  Widget createSubject({FakeAuthNotifier? notifier}) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => notifier ?? fakeAuthNotifier),
      ],
      child: const MaterialApp(
        home: LoginPage(),
      ),
    );
  }

  group('LoginPage & LoginForm Tests', () {
    testWidgets('renders all initial UI elements without any mock credential chips or bypass buttons', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('tAIdy'), findsOneWidget);
      expect(find.text('Sign In'), findsWidgets);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);

      // Verify no mock chips or bypass elements exist
      expect(find.text('developer'), findsNothing);
      expect(find.text('Quick Login'), findsNothing);
      expect(find.text('Bypass'), findsNothing);
    });

    testWidgets('validates email format with RFC 5322 regex and password complexity before submitting', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      final emailFinder = find.widgetWithText(TextFormField, 'Email');
      final passwordFinder = find.widgetWithText(TextFormField, 'Password');
      final signInButton = find.widgetWithText(ElevatedButton, 'Sign In');

      // 1. Empty fields
      await tester.tap(signInButton);
      await tester.pumpAndSettle();
      expect(fakeAuthNotifier.signInCalled, isFalse);
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);

      // 2. Invalid email format
      await tester.enterText(emailFinder, 'invalid-email');
      await tester.enterText(passwordFinder, 'Short1!');
      await tester.tap(signInButton);
      await tester.pumpAndSettle();
      expect(fakeAuthNotifier.signInCalled, isFalse);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Password must be at least 8 characters'), findsOneWidget);

      // 3. Password missing number
      await tester.enterText(emailFinder, 'user@example.com');
      await tester.enterText(passwordFinder, 'PasswordWithoutNumber!');
      await tester.tap(signInButton);
      await tester.pumpAndSettle();
      expect(fakeAuthNotifier.signInCalled, isFalse);
      expect(find.text('Password must contain at least 1 number'), findsOneWidget);

      // 4. Password missing special character
      await tester.enterText(passwordFinder, 'PasswordWithoutSpecial123');
      await tester.tap(signInButton);
      await tester.pumpAndSettle();
      expect(fakeAuthNotifier.signInCalled, isFalse);
      expect(find.text('Password must contain at least 1 special character'), findsOneWidget);
    });

    testWidgets('entering valid credentials triggers authProvider.signInWithEmailPassword', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      final emailFinder = find.widgetWithText(TextFormField, 'Email');
      final passwordFinder = find.widgetWithText(TextFormField, 'Password');
      final signInButton = find.widgetWithText(ElevatedButton, 'Sign In');

      await tester.enterText(emailFinder, 'developer@taidy.io');
      await tester.enterText(passwordFinder, 'SecretPass123!');
      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      expect(fakeAuthNotifier.signInCalled, isTrue);
      expect(fakeAuthNotifier.lastEmail, 'developer@taidy.io');
      expect(fakeAuthNotifier.lastPassword, 'SecretPass123!');
    });

    testWidgets('switching to Sign Up mode and submitting valid credentials triggers authProvider.signUp', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Tap Sign Up tab
      final signUpTab = find.text('Sign Up');
      await tester.tap(signUpTab);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ElevatedButton, 'Create Account'), findsOneWidget);

      final emailFinder = find.widgetWithText(TextFormField, 'Email');
      final passwordFinder = find.widgetWithText(TextFormField, 'Password');
      final createAccountButton = find.widgetWithText(ElevatedButton, 'Create Account');

      await tester.enterText(emailFinder, 'newuser@taidy.io');
      await tester.enterText(passwordFinder, 'NewSecurePassword123!');
      await tester.tap(createAccountButton);
      await tester.pumpAndSettle();

      expect(fakeAuthNotifier.signUpCalled, isTrue);
      expect(fakeAuthNotifier.lastEmail, 'newuser@taidy.io');
      expect(fakeAuthNotifier.lastPassword, 'NewSecurePassword123!');
    });

    testWidgets('disables submit button and shows loading indicator when isLoading is true', (tester) async {
      final loadingNotifier = FakeAuthNotifier(const AuthState(isLoading: true));

      await tester.pumpWidget(createSubject(notifier: loadingNotifier));
      await tester.pump(const Duration(seconds: 1));

      // Button is disabled, circular progress indicator is shown
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final emailFinder = find.widgetWithText(TextFormField, 'Email');
      final textField = tester.widget<TextFormField>(emailFinder);
      expect(textField.enabled, isFalse);

      final submitBtn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(submitBtn.onPressed, isNull);
    });

    testWidgets('tapping Forgot Password with valid email calls resetPassword', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      final emailFinder = find.widgetWithText(TextFormField, 'Email');
      await tester.enterText(emailFinder, 'reset@taidy.io');

      final forgotButton = find.text('Forgot password?');
      await tester.tap(forgotButton);
      await tester.pumpAndSettle();

      expect(fakeAuthNotifier.resetPasswordCalled, isTrue);
      expect(fakeAuthNotifier.lastEmail, 'reset@taidy.io');
    });
  });
}
