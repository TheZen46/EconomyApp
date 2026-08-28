import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/failures.dart';

abstract class AuthRepository {
  Stream<AuthState> get authStateChanges;
  User? get currentUser;
  Session? get currentSession;

  Future<Either<AuthFailure, User?>> signInWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  });
  Future<Either<AuthFailure, User?>> signUpWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  });
  Future<Either<AuthFailure, void>> signInWithGoogle({bool rememberMe = true});
  Future<Either<AuthFailure, User?>> recoverSession(String persistedSession);
  Future<Either<AuthFailure, void>> signOut();
  Future<Either<AuthFailure, void>> resetPassword(String email);
  Future<void> clearPersistedSession();
}
