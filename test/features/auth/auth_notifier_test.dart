import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show AuthState;
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/features/auth/domain/repositories/auth_repository.dart';
import 'package:t_aidy/features/auth/presentation/providers/auth_provider.dart';

class MockAuthRepository implements AuthRepository {
  final StreamController<supabase.AuthState> _streamController = StreamController<supabase.AuthState>.broadcast();
  User? user;
  Session? session;

  bool returnSuccess = true;
  AuthFailure? failureToReturn;

  @override
  Stream<supabase.AuthState> get authStateChanges => _streamController.stream;

  @override
  User? get currentUser => user;

  @override
  Session? get currentSession => session;

  @override
  Future<Either<AuthFailure, User?>> signInWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    if (!returnSuccess) {
      return Left(failureToReturn ?? const InvalidCredentialsFailure());
    }
    user = const User(id: 'mock-user-1', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-01-01');
    return Right(user);
  }

  @override
  Future<Either<AuthFailure, User?>> signUpWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    if (!returnSuccess) {
      return Left(failureToReturn ?? const EmailAlreadyInUseFailure());
    }
    user = const User(id: 'mock-user-2', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-01-01');
    return Right(user);
  }

  @override
  Future<Either<AuthFailure, void>> signInWithGoogle({bool rememberMe = true}) async {
    if (!returnSuccess) {
      return Left(failureToReturn ?? const NetworkFailure());
    }
    return const Right(null);
  }

  @override
  Future<Either<AuthFailure, void>> signOut() async {
    if (!returnSuccess) {
      return Left(failureToReturn ?? const InvalidCredentialsFailure());
    }
    user = null;
    session = null;
    return const Right(null);
  }

  @override
  Future<Either<AuthFailure, void>> resetPassword(String email) async {
    if (!returnSuccess) {
      return Left(failureToReturn ?? const UserNotFoundFailure());
    }
    return const Right(null);
  }

  @override
  Future<Either<AuthFailure, User?>> recoverSession(String persistedSession) async {
    if (!returnSuccess) {
      return Left(failureToReturn ?? const InvalidCredentialsFailure());
    }
    user = const User(id: 'recovered-user', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-01-01');
    return Right(user);
  }

  @override
  Future<void> clearPersistedSession() async {
    user = null;
    session = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'read':
            return mockStorage[methodCall.arguments['key']];
          case 'write':
            mockStorage[methodCall.arguments['key'] as String] = methodCall.arguments['value'] as String;
            return null;
          case 'delete':
            mockStorage.remove(methodCall.arguments['key']);
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

  group('AuthNotifier Tests', () {
    late MockAuthRepository mockRepo;
    late AuthNotifier notifier;

    setUp(() {
      mockStorage.clear();
      mockRepo = MockAuthRepository();
      notifier = AuthNotifier(mockRepo);
    });

    test('initial state is unauthenticated when no user exists', () {
      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.user, isNull);
    });

    test('signIn updates state to authenticated on success', () async {
      await notifier.signInWithEmailPassword('test@taidy.io', 'Password123!');
      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.user?.id, 'mock-user-1');
      expect(notifier.state.errorMessage, isNull);
    });

    test('signIn updates state with failure message on error', () async {
      mockRepo.returnSuccess = false;
      mockRepo.failureToReturn = const InvalidCredentialsFailure('Invalid email or password.');

      await notifier.signInWithEmailPassword('test@taidy.io', 'WrongPassword!');
      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.errorMessage, 'Invalid email or password.');
      expect(notifier.state.isLoading, isFalse);
    });

    test('signUp updates state to authenticated on success with session', () async {
      mockRepo.session = Session(
        accessToken: 'mock-token',
        tokenType: 'bearer',
        user: const User(id: 'mock-user-2', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-01-01'),
      );

      await notifier.signUp(email: 'new@taidy.io', password: 'Password123!');
      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.user?.id, 'mock-user-2');
    });

    test('signUp prompts email confirmation when session is null', () async {
      mockRepo.session = null;

      await notifier.signUp(email: 'new@taidy.io', password: 'Password123!');
      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.errorMessage, 'Check your email to confirm your account.');
    });

    test('signUp updates state with failure message when email is already in use', () async {
      mockRepo.returnSuccess = false;
      mockRepo.failureToReturn = const EmailAlreadyInUseFailure('Email already exists');

      await notifier.signUp(email: 'taken@taidy.io', password: 'Password123!');
      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.errorMessage, 'Email already exists');
    });

    test('signOut resets state to unauthenticated', () async {
      // First authenticate
      await notifier.signInWithEmailPassword('test@taidy.io', 'Password123!');
      expect(notifier.state.status, AuthStatus.authenticated);

      // Now sign out
      await notifier.signOut();
      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.user, isNull);
    });
  });
}
