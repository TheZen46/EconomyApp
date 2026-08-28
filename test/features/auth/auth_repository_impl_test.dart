import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/core/services/secure_storage_service.dart';
import 'package:t_aidy/features/auth/data/repositories/auth_repository_impl.dart';

class MockGotrueAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> getItem({required String key}) async => _storage[key];

  @override
  Future<void> removeItem({required String key}) async => _storage.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async => _storage[key] = value;
}

class FakeGoTrueClient extends GoTrueClient {
  FakeGoTrueClient()
      : super(
          url: 'https://fake.supabase.co/auth/v1',
          headers: {},
          asyncStorage: MockGotrueAsyncStorage(),
        );

  bool throwException = false;
  AuthException? exceptionToThrow;
  Object? genericExceptionToThrow;

  User? mockUser;
  Session? mockSession;
  OAuthProvider? capturedOAuthProvider;

  final StreamController<AuthState> _authStateController = StreamController<AuthState>.broadcast();

  @override
  Stream<AuthState> get onAuthStateChange => _authStateController.stream;

  @override
  User? get currentUser => mockUser;

  @override
  Session? get currentSession => mockSession;

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    if (throwException) {
      if (exceptionToThrow != null) throw exceptionToThrow!;
      if (genericExceptionToThrow != null) throw genericExceptionToThrow!;
    }
    return AuthResponse(session: mockSession, user: mockUser);
  }

  @override
  Future<AuthResponse> signUp({
    String? email,
    String? phone,
    required String password,
    String? emailRedirectTo,
    Map<String, dynamic>? data,
    String? captchaToken,
    OtpChannel channel = OtpChannel.sms,
  }) async {
    if (throwException) {
      if (exceptionToThrow != null) throw exceptionToThrow!;
      if (genericExceptionToThrow != null) throw genericExceptionToThrow!;
    }
    return AuthResponse(session: mockSession, user: mockUser);
  }

  @override
  Future<OAuthResponse> getOAuthSignInUrl({
    required OAuthProvider provider,
    String? redirectTo,
    String? scopes,
    Map<String, String>? queryParams,
  }) async {
    capturedOAuthProvider = provider;
    if (throwException) {
      if (exceptionToThrow != null) throw exceptionToThrow!;
      if (genericExceptionToThrow != null) throw genericExceptionToThrow!;
      throw const AuthException('OAuth failed', statusCode: '500');
    }
    return OAuthResponse(provider: provider, url: 'https://fake.supabase.co/auth/v1/authorize');
  }

  Future<bool> signInWithOAuth(
    OAuthProvider provider, {
    String? redirectTo,
    String? scopes,
    Map<String, String>? queryParams,
    LaunchMode authScreenLaunchMode = LaunchMode.platformDefault,
  }) async {
    capturedOAuthProvider = provider;
    if (throwException) {
      if (exceptionToThrow != null) throw exceptionToThrow!;
      if (genericExceptionToThrow != null) throw genericExceptionToThrow!;
      throw const AuthException('OAuth failed', statusCode: '500');
    }
    return true;
  }

  @override
  Future<AuthResponse> recoverSession(String jsonStr) async {
    if (throwException) {
      if (exceptionToThrow != null) throw exceptionToThrow!;
      if (genericExceptionToThrow != null) throw genericExceptionToThrow!;
      throw const AuthException('Invalid session', statusCode: '401');
    }
    return AuthResponse(session: mockSession, user: mockUser);
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    if (throwException) {
      if (exceptionToThrow != null) throw exceptionToThrow!;
      if (genericExceptionToThrow != null) throw genericExceptionToThrow!;
      throw const AuthException('SignOut failed', statusCode: '500');
    }
  }

  @override
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) async {
    if (throwException) {
      if (exceptionToThrow != null) throw exceptionToThrow!;
      if (genericExceptionToThrow != null) throw genericExceptionToThrow!;
      throw const AuthException('Reset failed', statusCode: '500');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupabaseClient extends SupabaseClient {
  final FakeGoTrueClient _fakeAuth;

  FakeSupabaseClient(this._fakeAuth)
      : super('https://fake.supabase.co', 'fakeAnonKey');

  @override
  GoTrueClient get auth => _fakeAuth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async => true,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        switch (call.method) {
          case 'read':
            final key = call.arguments['key'] as String;
            return mockStorage[key];
          case 'write':
            final key = call.arguments['key'] as String;
            final value = call.arguments['value'] as String;
            mockStorage[key] = value;
            return null;
          case 'delete':
            final key = call.arguments['key'] as String;
            mockStorage.remove(key);
            return null;
          case 'deleteAll':
            mockStorage.clear();
            return null;
          default:
            return null;
        }
      },
    );
  });

  group('AuthRepository Tests', () {
    late FakeGoTrueClient fakeGoTrue;
    late FakeSupabaseClient fakeClient;
    late AuthRepositoryImpl repository;
    late User testUser;
    late Session testSession;

    setUp(() {
      mockStorage.clear();
      fakeGoTrue = FakeGoTrueClient();
      fakeClient = FakeSupabaseClient(fakeGoTrue);
      repository = AuthRepositoryImpl(client: fakeClient, authClient: fakeGoTrue);

      testUser = const User(
        id: 'user-123',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01',
      );
      testSession = Session(
        accessToken: 'fake-access-token',
        tokenType: 'bearer',
        user: testUser,
        refreshToken: 'fake-refresh-token',
      );
      fakeGoTrue.mockUser = testUser;
      fakeGoTrue.mockSession = testSession;
    });

    test('signInWithEmailPassword returns User on success and saves session when rememberMe=true', () async {
      final result = await repository.signInWithEmailPassword('test@taidy.io', 'Password123!', rememberMe: true);
      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should not fail'),
        (user) => expect(user?.id, 'user-123'),
      );
      expect(mockStorage[SecretKeys.supabaseRefreshToken], 'fake-refresh-token');
      expect(mockStorage[SecretKeys.rememberMe], 'true');
    });

    test('signInWithEmailPassword purges session when rememberMe=false', () async {
      mockStorage[SecretKeys.supabaseRefreshToken] = 'old-token';
      final result = await repository.signInWithEmailPassword('test@taidy.io', 'Password123!', rememberMe: false);
      expect(result.isRight(), isTrue);
      expect(mockStorage.containsKey(SecretKeys.supabaseRefreshToken), isFalse);
      expect(mockStorage[SecretKeys.rememberMe], 'false');
    });

    test('signUpWithEmailPassword returns User on success', () async {
      final result = await repository.signUpWithEmailPassword('new@taidy.io', 'Password123!', rememberMe: true);
      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should not fail'),
        (user) => expect(user?.id, 'user-123'),
      );
    });

    test('signUpWithEmailPassword handles rememberMe=false', () async {
      final result = await repository.signUpWithEmailPassword('new@taidy.io', 'Password123!', rememberMe: false);
      expect(result.isRight(), isTrue);
      expect(mockStorage[SecretKeys.rememberMe], 'false');
    });

    test('signInWithEmailPassword maps Invalid login credentials to InvalidCredentialsFailure', () async {
      fakeGoTrue.throwException = true;
      fakeGoTrue.exceptionToThrow = const AuthException('Invalid login credentials', statusCode: '400', code: 'invalid_credentials');

      final result = await repository.signInWithEmailPassword('test@taidy.io', 'WrongPassword!');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<InvalidCredentialsFailure>()),
        (user) => fail('Should not succeed'),
      );
    });

    test('signInWithEmailPassword maps User not found to UserNotFoundFailure', () async {
      fakeGoTrue.throwException = true;
      fakeGoTrue.exceptionToThrow = const AuthException('User not found', statusCode: '404', code: 'user_not_found');

      final result = await repository.signInWithEmailPassword('notfound@taidy.io', 'Password123!');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<UserNotFoundFailure>()),
        (user) => fail('Should not succeed'),
      );
    });

    test('signUpWithEmailPassword maps already registered error to EmailAlreadyInUseFailure', () async {
      fakeGoTrue.throwException = true;
      fakeGoTrue.exceptionToThrow = const AuthException('User already registered', statusCode: '422', code: 'user_already_exists');

      final result = await repository.signUpWithEmailPassword('existing@taidy.io', 'Password123!');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<EmailAlreadyInUseFailure>()),
        (user) => fail('Should not succeed'),
      );
    });

    test('maps socket / connection failure to NetworkFailure', () async {
      fakeGoTrue.throwException = true;
      fakeGoTrue.genericExceptionToThrow = 'SocketException: Failed host lookup: supabase.co';

      final result = await repository.signInWithEmailPassword('test@taidy.io', 'Password123!');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<NetworkFailure>()),
        (user) => fail('Should not succeed'),
      );
    });

    test('signInWithGoogle triggers OAuth with Google provider', () async {
      final result = await repository.signInWithGoogle();
      expect(result.isRight(), isTrue);
      expect(fakeGoTrue.capturedOAuthProvider, OAuthProvider.google);
    });

    test('signInWithGoogle maps failure when OAuth throws', () async {
      fakeGoTrue.throwException = true;
      fakeGoTrue.exceptionToThrow = const AuthException('OAuth failed', statusCode: '500');

      final result = await repository.signInWithGoogle();
      expect(result.isLeft(), isTrue);
    });

    test('recoverSession restores user session and updates tokens', () async {
      final result = await repository.recoverSession('{"access_token":"fake"}');
      expect(result.isRight(), isTrue);
      expect(mockStorage[SecretKeys.supabaseRefreshToken], 'fake-refresh-token');
    });

    test('recoverSession maps failure on invalid session string', () async {
      fakeGoTrue.throwException = true;
      fakeGoTrue.exceptionToThrow = const AuthException('Invalid session', statusCode: '401');

      final result = await repository.recoverSession('invalid-json');
      expect(result.isLeft(), isTrue);
    });

    test('signOut purges auth data and returns Right', () async {
      mockStorage[SecretKeys.supabaseRefreshToken] = 'token';
      final signOutResult = await repository.signOut();
      expect(signOutResult.isRight(), isTrue);
      expect(mockStorage.containsKey(SecretKeys.supabaseRefreshToken), isFalse);
    });

    test('signOut purges auth data even when remote signOut fails', () async {
      mockStorage[SecretKeys.supabaseRefreshToken] = 'token';
      fakeGoTrue.throwException = true;
      fakeGoTrue.exceptionToThrow = const AuthException('Network error', statusCode: '500');

      final signOutResult = await repository.signOut();
      expect(signOutResult.isLeft(), isTrue);
      expect(mockStorage.containsKey(SecretKeys.supabaseRefreshToken), isFalse);
    });

    test('clearPersistedSession purges all secure storage items', () async {
      mockStorage[SecretKeys.supabaseRefreshToken] = 'token';
      await repository.clearPersistedSession();
      expect(mockStorage.containsKey(SecretKeys.supabaseRefreshToken), isFalse);
    });

    test('resetPassword sends recovery email successfully', () async {
      final resetResult = await repository.resetPassword('test@taidy.io');
      expect(resetResult.isRight(), isTrue);
    });

    test('resetPassword maps failure on error', () async {
      fakeGoTrue.throwException = true;
      fakeGoTrue.exceptionToThrow = const AuthException('User not found', statusCode: '404', code: 'user_not_found');

      final resetResult = await repository.resetPassword('missing@taidy.io');
      expect(resetResult.isLeft(), isTrue);
    });

    test('exposes auth getters and streams correctly', () {
      expect(repository.currentUser?.id, 'user-123');
      expect(repository.currentSession?.accessToken, 'fake-access-token');
      expect(repository.authStateChanges, isA<Stream<AuthState>>());
    });
  });
}
