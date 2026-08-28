import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show AuthState;
import 'package:t_aidy/core/services/secure_storage_service.dart';
import 'package:t_aidy/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:t_aidy/features/auth/presentation/providers/auth_provider.dart';

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

  User? mockUser;
  Session? mockSession;
  bool throwException = false;
  String? lastRecoveredSession;

  final StreamController<supabase.AuthState> _authStateController = StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get onAuthStateChange => _authStateController.stream;

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
    return AuthResponse(session: mockSession, user: mockUser);
  }

  @override
  Future<AuthResponse> recoverSession(String jsonStr) async {
    lastRecoveredSession = jsonStr;
    return AuthResponse(session: mockSession, user: mockUser);
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    mockSession = null;
    mockUser = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockSecureStorage = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'read':
            final key = methodCall.arguments['key'] as String;
            return mockSecureStorage[key];
          case 'write':
            final key = methodCall.arguments['key'] as String;
            final value = methodCall.arguments['value'] as String;
            mockSecureStorage[key] = value;
            return null;
          case 'delete':
            final key = methodCall.arguments['key'] as String;
            mockSecureStorage.remove(key);
            return null;
          case 'deleteAll':
            mockSecureStorage.clear();
            return null;
          default:
            return null;
        }
      },
    );
  });

  setUp(() {
    mockSecureStorage.clear();
  });

  group('SecureStorageService Auth Operations', () {
    test('saves, retrieves, and deletes refresh token and persisted session', () async {
      await SecureStorageService.saveRefreshToken('ref-12345');
      expect(await SecureStorageService.getRefreshToken(), 'ref-12345');

      await SecureStorageService.savePersistedSession('{"access_token":"abc"}');
      expect(await SecureStorageService.getPersistedSession(), '{"access_token":"abc"}');

      await SecureStorageService.setRememberMe(true);
      expect(await SecureStorageService.getRememberMe(), isTrue);

      await SecureStorageService.purgeAuthData();
      expect(await SecureStorageService.getRefreshToken(), isNull);
      expect(await SecureStorageService.getPersistedSession(), isNull);
    });
  });

  group('AuthRepositoryImpl Session Persistence', () {
    late FakeGoTrueClient fakeGoTrue;
    late AuthRepositoryImpl repository;
    late User testUser;
    late Session testSession;

    setUp(() {
      fakeGoTrue = FakeGoTrueClient();
      repository = AuthRepositoryImpl(authClient: fakeGoTrue);

      testUser = const User(
        id: 'persisted-user',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01',
      );
      testSession = Session(
        accessToken: 'acc-123',
        refreshToken: 'ref-999',
        tokenType: 'bearer',
        user: testUser,
      );
      fakeGoTrue.mockUser = testUser;
      fakeGoTrue.mockSession = testSession;
    });

    test('signIn with rememberMe=true persists refresh token and session JSON', () async {
      final result = await repository.signInWithEmailPassword(
        'user@taidy.io',
        'Password123!',
        rememberMe: true,
      );

      expect(result.isRight(), isTrue);
      expect(await SecureStorageService.getRefreshToken(), 'ref-999');
      expect(await SecureStorageService.getPersistedSession(), contains('ref-999'));
      expect(await SecureStorageService.getRememberMe(), isTrue);
    });

    test('signIn with rememberMe=false purges secure storage', () async {
      // First populate storage
      await SecureStorageService.saveRefreshToken('old-token');

      final result = await repository.signInWithEmailPassword(
        'user@taidy.io',
        'Password123!',
        rememberMe: false,
      );

      expect(result.isRight(), isTrue);
      expect(await SecureStorageService.getRefreshToken(), isNull);
      expect(await SecureStorageService.getPersistedSession(), isNull);
      expect(await SecureStorageService.getRememberMe(), isFalse);
    });

    test('signOut purges all local auth tokens and session from SecureStorageService', () async {
      await SecureStorageService.saveRefreshToken('token-to-delete');
      await SecureStorageService.savePersistedSession('session-to-delete');

      final result = await repository.signOut();
      expect(result.isRight(), isTrue);

      expect(await SecureStorageService.getRefreshToken(), isNull);
      expect(await SecureStorageService.getPersistedSession(), isNull);
    });
  });

  group('AuthNotifier Cold Start Session Restoration', () {
    test('cold start with rememberMe=true and valid session restores authenticated state', () async {
      await SecureStorageService.setRememberMe(true);
      await SecureStorageService.savePersistedSession('{"access_token":"token-abc"}');

      final mockRepo = FakeGoTrueClient();
      final user = const User(id: 'restored-user', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-01-01');
      mockRepo.mockUser = user;
      mockRepo.mockSession = Session(accessToken: 'token-abc', refreshToken: 'ref-abc', tokenType: 'bearer', user: user);

      final repo = AuthRepositoryImpl(authClient: mockRepo);
      final notifier = AuthNotifier(repo);

      // Allow async _initialize to complete
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.user?.id, 'restored-user');
    });

    test('cold start with rememberMe=false starts unauthenticated and clears session', () async {
      await SecureStorageService.setRememberMe(false);
      await SecureStorageService.savePersistedSession('{"access_token":"token-abc"}');

      final mockRepo = FakeGoTrueClient();
      final repo = AuthRepositoryImpl(authClient: mockRepo);
      final notifier = AuthNotifier(repo);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.user, isNull);
    });
  });
}
