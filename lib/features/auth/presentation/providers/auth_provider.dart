import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../../sync/presentation/providers/sync_provider.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

enum AuthStatus { unknown, authenticated, unauthenticated, loading }

class AuthState {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.user,
    this.errorMessage,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  StreamSubscription<AuthState>? _authSubscription;

  AuthNotifier(this._repository) : super(const AuthState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    final rememberMe = await SecureStorageService.getRememberMe();
    if (rememberMe) {
      final persistedSession = await SecureStorageService.getPersistedSession();
      if (persistedSession != null && persistedSession.isNotEmpty) {
        final result = await _repository.recoverSession(persistedSession);
        result.fold(
          (failure) {
            debugPrint('Session recovery failed: ${failure.message}');
            final user = _repository.currentUser;
            if (user != null) {
              state = AuthState(
                status: AuthStatus.authenticated,
                user: user,
              );
            } else {
              state = const AuthState(status: AuthStatus.unauthenticated);
            }
          },
          (user) {
            if (user != null) {
              state = AuthState(
                status: AuthStatus.authenticated,
                user: user,
              );
            } else {
              state = const AuthState(status: AuthStatus.unauthenticated);
            }
          },
        );
      } else {
        final user = _repository.currentUser;
        if (user != null) {
          state = AuthState(
            status: AuthStatus.authenticated,
            user: user,
          );
        } else {
          state = const AuthState(status: AuthStatus.unauthenticated);
        }
      }
    } else {
      // Remember me disabled: do not restore persisted session on cold start
      await _repository.clearPersistedSession();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }

    // Listen for auth state changes (login, logout, token refresh)
    _repository.authStateChanges.listen((data) {
      final event = data.event;
      final session = data.session;

      debugPrint('Auth Event: $event');

      switch (event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          state = AuthState(
            status: AuthStatus.authenticated,
            user: session?.user,
          );
          break;
        case AuthChangeEvent.signedOut:
          state = const AuthState(status: AuthStatus.unauthenticated);
          break;
        case AuthChangeEvent.initialSession:
          if (session != null && rememberMe) {
            state = AuthState(
              status: AuthStatus.authenticated,
              user: session.user,
            );
          } else if (!rememberMe) {
            state = const AuthState(status: AuthStatus.unauthenticated);
          }
          break;
        default:
          break;
      }
    });
  }

  // ── Email/Password Sign Up ──────────────────────────────────────────────

  Future<void> signUp({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    state = state.copyWith(isLoading: true, status: AuthStatus.loading, errorMessage: null);
    final result = await _repository.signUpWithEmailPassword(
      email,
      password,
      rememberMe: rememberMe,
    );
    result.fold(
      (failure) {
        state = state.copyWith(
          isLoading: false,
          status: AuthStatus.unauthenticated,
          errorMessage: failure.message,
        );
      },
      (user) {
        if (user != null && _repository.currentSession == null) {
          // Email confirmation required
          state = state.copyWith(
            isLoading: false,
            status: AuthStatus.unauthenticated,
            errorMessage: 'Check your email to confirm your account.',
          );
        } else if (user != null) {
          state = AuthState(
            status: AuthStatus.authenticated,
            user: user,
          );
        }
      },
    );
  }

  Future<void> signInWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    await signIn(email: email, password: password, rememberMe: rememberMe);
  }

  // ── Email/Password Sign In ──────────────────────────────────────────────

  Future<void> signIn({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    state = state.copyWith(isLoading: true, status: AuthStatus.loading, errorMessage: null);
    final result = await _repository.signInWithEmailPassword(
      email,
      password,
      rememberMe: rememberMe,
    );
    result.fold(
      (failure) {
        state = state.copyWith(
          isLoading: false,
          status: AuthStatus.unauthenticated,
          errorMessage: failure.message,
        );
      },
      (user) {
        if (user != null) {
          state = AuthState(
            status: AuthStatus.authenticated,
            user: user,
          );
        }
      },
    );
  }

  // ── Google Sign In ──────────────────────────────────────────────────────

  Future<void> signInWithGoogle({bool rememberMe = true}) async {
    state = state.copyWith(isLoading: true, status: AuthStatus.loading, errorMessage: null);
    final result = await _repository.signInWithGoogle(rememberMe: rememberMe);
    result.fold(
      (failure) {
        state = state.copyWith(
          isLoading: false,
          status: AuthStatus.unauthenticated,
          errorMessage: failure.message,
        );
      },
      (_) {
        // Handled via onAuthStateChange callback
      },
    );
  }

  // ── Sign Out ────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, status: AuthStatus.loading);
    final result = await _repository.signOut();
    result.fold(
      (failure) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: failure.message,
        );
      },
      (_) {
        state = const AuthState(status: AuthStatus.unauthenticated);
      },
    );
  }

  // ── Password Reset ─────────────────────────────────────────────────────

  Future<void> resetPassword(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _repository.resetPassword(email);
    result.fold(
      (failure) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: failure.message,
        );
      },
      (_) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Password reset email sent. Check your inbox.',
        );
      },
    );
  }

  /// Clear any displayed error message.
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

// ── Riverpod Providers ──────────────────────────────────────────────────────

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl();
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthNotifier(repository);
});

/// Convenience provider: is there a valid Supabase session right now?
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

/// Convenience provider: the currently logged in Supabase User, if any.
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).user;
});

/// Convenience provider: the current AuthStatus.
final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authProvider).status;
});

/// StreamProvider that emits every Supabase AuthChangeEvent.
/// The router uses this to reactively re-evaluate the redirect guard
/// whenever the session changes (sign in, sign out, token refresh, expiry).
final authStateStreamProvider = StreamProvider<AuthChangeEvent>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges.map((data) => data.event);
});

// ── Router Notifier ─────────────────────────────────────────────────────────

/// A [ChangeNotifier] that notifies GoRouter whenever the Supabase auth
/// stream emits a new event. Wire this to GoRouter.refreshListenable so
/// the redirect: callback re-runs automatically on every session change.
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(Ref ref) {
    // Re-run notifyListeners every time authProvider state changes
    ref.listen<AuthState>(
      authProvider,
      (prev, next) => notifyListeners(),
    );
    // Also re-run notifyListeners every time the auth stream emits
    ref.listen<AsyncValue<AuthChangeEvent>>(
      authStateStreamProvider,
      (prev, next) => notifyListeners(),
    );
    // Re-run notifyListeners when initial synchronization state changes
    ref.listen<bool>(
      initialSyncCompletedProvider,
      (prev, next) => notifyListeners(),
    );
  }
}

/// Provider that exposes the [RouterNotifier] singleton.
final routerNotifierProvider = ChangeNotifierProvider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});


