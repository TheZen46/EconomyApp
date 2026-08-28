import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final GoTrueClient _auth;

  AuthRepositoryImpl({SupabaseClient? client, GoTrueClient? authClient})
      : _auth = authClient ?? (client != null ? client.auth : Supabase.instance.client.auth);

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
            await SecureStorageService.saveRefreshToken(refreshToken);
          }
          final sessionJson = jsonEncode(session.toJson());
          await SecureStorageService.savePersistedSession(sessionJson);
          await SecureStorageService.setRememberMe(true);
        } else {
          await SecureStorageService.purgeAuthData();
          await SecureStorageService.setRememberMe(false);
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
            await SecureStorageService.saveRefreshToken(refreshToken);
          }
          final sessionJson = jsonEncode(session.toJson());
          await SecureStorageService.savePersistedSession(sessionJson);
          await SecureStorageService.setRememberMe(true);
        } else {
          await SecureStorageService.purgeAuthData();
          await SecureStorageService.setRememberMe(false);
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
      await SecureStorageService.setRememberMe(rememberMe);
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
        await SecureStorageService.saveRefreshToken(session.refreshToken!);
        await SecureStorageService.savePersistedSession(jsonEncode(session.toJson()));
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
      await SecureStorageService.purgeAuthData();
      return const Right(null);
    } catch (e) {
      await SecureStorageService.purgeAuthData();
      return Left(_mapException(e));
    }
  }

  @override
  Future<void> clearPersistedSession() async {
    await SecureStorageService.purgeAuthData();
  }

  @override
  Future<Either<AuthFailure, void>> resetPassword(String email) async {
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
          msg.contains('failed host lookup')) {
        return NetworkFailure(error.message);
      }

      return InvalidCredentialsFailure(error.message);
    }

    final str = error.toString().toLowerCase();
    if (str.contains('socket') ||
        str.contains('network') ||
        str.contains('connection') ||
        str.contains('failed host lookup')) {
      return const NetworkFailure('Network error. Please check your connection.');
    }

    return InvalidCredentialsFailure(error.toString());
  }
}
