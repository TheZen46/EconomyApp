import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
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
  final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSubscription;

  AuthNotifier(this._client) : super(const AuthState()) {
    _initialize();
  }

  void _initialize() {
    // Check current session on startup
    final session = _client.auth.currentSession;
    if (session != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: _client.auth.currentUser,
      );
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }

    // Listen for auth state changes (login, logout, token refresh)
    _client.auth.onAuthStateChange.listen((data) {
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
          if (session != null) {
            state = AuthState(
              status: AuthStatus.authenticated,
              user: session.user,
            );
          } else {
            state = const AuthState(status: AuthStatus.unauthenticated);
          }
          break;
        default:
          break;
      }
    });
  }

  // ── Email/Password Sign Up ──────────────────────────────────────────────

  Future<void> signUp({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user != null && response.session == null) {
        // Email confirmation required
        state = state.copyWith(
          isLoading: false,
          status: AuthStatus.unauthenticated,
          errorMessage: 'Check your email to confirm your account.',
        );
      } else if (response.user != null) {
        state = AuthState(
          status: AuthStatus.authenticated,
          user: response.user,
        );
      }
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'An unexpected error occurred. Please try again.',
      );
      debugPrint('Auth signUp error: $e');
    }
  }

  // ── Email/Password Sign In ──────────────────────────────────────────────

  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session != null) {
        state = AuthState(
          status: AuthStatus.authenticated,
          user: response.user,
        );
      }
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'An unexpected error occurred. Please try again.',
      );
      debugPrint('Auth signIn error: $e');
    }
  }

  // ── Sign Out ────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      await _client.auth.signOut();
      state = const AuthState(status: AuthStatus.unauthenticated);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to sign out. Please try again.',
      );
      debugPrint('Auth signOut error: $e');
    }
  }

  // ── Password Reset ─────────────────────────────────────────────────────

  Future<void> resetPassword(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _client.auth.resetPasswordForEmail(email);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Password reset email sent. Check your inbox.',
      );
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to send reset email.',
      );
    }
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

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final client = Supabase.instance.client;
  return AuthNotifier(client);
});

/// Convenience provider: is there a valid Supabase session right now?
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

/// StreamProvider that emits every Supabase AuthChangeEvent.
/// The router uses this to reactively re-evaluate the redirect guard
/// whenever the session changes (sign in, sign out, token refresh, expiry).
final authStateStreamProvider = StreamProvider<AuthChangeEvent>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange
      .map((data) => data.event);
});

// ── Router Notifier ─────────────────────────────────────────────────────────

/// A [ChangeNotifier] that notifies GoRouter whenever the Supabase auth
/// stream emits a new event. Wire this to GoRouter.refreshListenable so
/// the redirect: callback re-runs automatically on every session change.
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(Ref ref) {
    // Re-run notifyListeners every time the auth stream emits
    ref.listen<AsyncValue<AuthChangeEvent>>(
      authStateStreamProvider,
      (_, __) => notifyListeners(),
    );
  }
}

/// Provider that exposes the [RouterNotifier] singleton.
final routerNotifierProvider = ChangeNotifierProvider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

