import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/providers/supabase_providers.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final GoTrueClient _auth;
  final SecureStorageService _secureStorage;
  final bool _isOffline;

  static SupabaseClient _resolveDefaultClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return offlineSupabaseClient;
    }
  }

  AuthRepositoryImpl({
    SupabaseClient? client,
    GoTrueClient? authClient,
    SecureStorageService? secureStorage,
  })  : _isOffline = (client == offlineSupabaseClient) ||
            (authClient == offlineSupabaseClient.auth) ||
            (client == null && authClient == null && _resolveDefaultClient() == offlineSupabaseClient),
        _auth = authClient ??
            (client != null ? client.auth : _resolveDefaultClient().auth),
        _secureStorage = secureStorage ?? SecureStorageService();

  @override
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Session? get currentSession => _auth.currentSession;

  @override
  Future<Either<AuthFailure, User?>> signInWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    if (_isOffline) {
      return const Left(
        NetworkFailure(
          'Cloud authentication is unavailable in offline mode. Please configure SUPABASE_URL or continue in offline mode.',
        ),
      );
    }
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );

      final session = response.session;
      if (session != null) {
        if (rememberMe) {
          final refreshToken = session.refreshToken;
          if (refreshToken != null && refreshToken.isNotEmpty) {
            await _secureStorage.saveRefreshToken(refreshToken);
          }
          final sessionJson = jsonEncode(session.toJson());
          await _secureStorage.savePersistedSession(sessionJson);
          await _secureStorage.setRememberMe(true);
        } else {
          await _secureStorage.purgeAuthData();
          await _secureStorage.setRememberMe(false);
        }
      }

      return Right(response.user);
    } catch (e) {
      return Left(_mapException(e));
    }
  }

  @override
  Future<Either<AuthFailure, User?>> signUpWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    if (_isOffline) {
      return const Left(
        NetworkFailure(
          'Cloud authentication is unavailable in offline mode. Please configure SUPABASE_URL or continue in offline mode.',
        ),
      );
    }
    try {
      final response = await _auth.signUp(
        email: email,
        password: password,
      );

      final session = response.session;
      if (session != null) {
        if (rememberMe) {
          final refreshToken = session.refreshToken;
          if (refreshToken != null && refreshToken.isNotEmpty) {
            await _secureStorage.saveRefreshToken(refreshToken);
          }
          final sessionJson = jsonEncode(session.toJson());
          await _secureStorage.savePersistedSession(sessionJson);
          await _secureStorage.setRememberMe(true);
        } else {
          await _secureStorage.purgeAuthData();
          await _secureStorage.setRememberMe(false);
        }
      }

      return Right(response.user);
    } catch (e) {
      return Left(_mapException(e));
    }
  }

  @override
  Future<Either<AuthFailure, void>> signInWithGoogle({bool rememberMe = true}) async {
    try {
      await _secureStorage.setRememberMe(rememberMe);
      await _auth.signInWithOAuth(OAuthProvider.google);
      return const Right(null);
    } catch (e) {
      return Left(_mapException(e));
    }
  }

  @override
  Future<Either<AuthFailure, User?>> recoverSession(String persistedSession) async {
    try {
      final response = await _auth.recoverSession(persistedSession);
      final session = response.session;
      if (session != null && session.refreshToken != null) {
        await _secureStorage.saveRefreshToken(session.refreshToken!);
        await _secureStorage.savePersistedSession(jsonEncode(session.toJson()));
      }
      return Right(response.user);
    } catch (e) {
      return Left(_mapException(e));
    }
  }

  @override
  Future<Either<AuthFailure, void>> signOut() async {
    try {
      await _auth.signOut();
      await _secureStorage.purgeAuthData();
      return const Right(null);
    } catch (e) {
      await _secureStorage.purgeAuthData();
      return Left(_mapException(e));
    }
  }

  @override
  Future<void> clearPersistedSession() async {
    await _secureStorage.purgeAuthData();
    // The Supabase client restores its own copy of the session at startup.
    // Signing out locally removes it; revoking it on the server may fail
    // offline, which does not matter here.
    try {
      await _auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  @override
  Future<Either<AuthFailure, void>> resetPassword(String email) async {
    if (_isOffline) {
      return const Left(
        NetworkFailure(
          'Cloud authentication is unavailable in offline mode. Please configure SUPABASE_URL or continue in offline mode.',
        ),
      );
    }
    try {
      await _auth.resetPasswordForEmail(email);
      return const Right(null);
    } catch (e) {
      return Left(_mapException(e));
    }
  }

  AuthFailure _mapException(Object error) {
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      final code = error.code?.toLowerCase() ?? '';

      if (msg.contains('invalid login credentials') ||
          msg.contains('invalid credential') ||
          msg.contains('invalid password') ||
          code == 'invalid_credentials' ||
          code == 'invalid_grant') {
        return InvalidCredentialsFailure(error.message);
      }

      if (msg.contains('user not found') || code == 'user_not_found') {
        return UserNotFoundFailure(error.message);
      }

      if (msg.contains('already registered') ||
          msg.contains('already in use') ||
          msg.contains('user already exists') ||
          code == 'user_already_exists') {
        return EmailAlreadyInUseFailure(error.message);
      }

      if (msg.contains('network') ||
          msg.contains('connection') ||
          msg.contains('socket') ||
          msg.contains('timeout') ||
          msg.contains('failed host lookup') ||
          msg.contains('failed to fetch')) {
        return NetworkFailure(error.message);
      }

      return InvalidCredentialsFailure(error.message);
    }

    final str = error.toString().toLowerCase();
    if (str.contains('offline.invalid')) {
      return const NetworkFailure(
        'Cloud authentication is unavailable in offline mode. Please configure SUPABASE_URL or continue in offline mode.',
      );
    }
    if (str.contains('socket') ||
        str.contains('network') ||
        str.contains('connection') ||
        str.contains('failed host lookup') ||
        str.contains('failed to fetch') ||
        str.contains('clientexception')) {
      return const NetworkFailure('Network connection error. Please check your connection or continue in offline mode.');
    }

    return InvalidCredentialsFailure(error.toString());
  }
}
