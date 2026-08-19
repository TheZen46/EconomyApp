import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/receipt_scanning/presentation/pages/home_page.dart';
import '../../features/receipt_scanning/presentation/pages/scan_page.dart';
import '../../features/receipt_scanning/presentation/pages/review_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/settings/presentation/pages/taxonomy_settings_page.dart';
import '../../features/receipt_scanning/presentation/pages/price_watch_page.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../../features/settings/presentation/pages/integrations_page.dart';
import '../../features/evault/presentation/pages/vault_page.dart';
import '../../features/settings/presentation/pages/model_manager_page.dart';
import '../../features/boxes/presentation/pages/boxes_page.dart';
import '../../features/invoices/presentation/pages/invoices_page.dart';

// ── Route Path Constants ────────────────────────────────────────────────────
abstract class AppRoutes {
  static const login = '/';
  static const home = '/home';
  static const settings = '/settings';
  static const priceWatch = '/price_watch';
  static const scan = '/scan';
  static const review = '/review';
  static const taxonomy = '/taxonomy';
  static const integrations = '/integrations';
  static const vault = '/vault';
  static const modelManager = '/model_manager';
  static const boxes = '/boxes';
  static const invoices = '/invoices';
}

// ── Public (unauthenticated) routes ─────────────────────────────────────────
const _publicRoutes = {AppRoutes.login};

final routerProvider = Provider<GoRouter>((ref) {
  // RouterNotifier is a ChangeNotifier wired to the Supabase auth stream.
  // GoRouter calls refreshListenable.addListener so it re-runs redirect:
  // automatically on every auth event (signIn, signOut, tokenRefresh, expiry).
  final notifier = ref.watch(routerNotifierProvider);

  // Determine the correct start location based on the existing Supabase session.
  // supabase_flutter persists the token natively — no Hive flag needed.
  final hasSession = Supabase.instance.client.auth.currentSession != null;

  return GoRouter(
    initialLocation: hasSession ? AppRoutes.home : AppRoutes.login,

    // Reactive refresh: every Supabase auth event triggers a re-evaluation
    // of the redirect callback without needing a full widget rebuild.
    refreshListenable: notifier,

    // ── Route Guard ────────────────────────────────────────────────────────
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final location = state.matchedLocation;
      final isPublicRoute = _publicRoutes.contains(location);

      // While the auth status is still being determined (cold start), hold on
      // the login page — never allow a protected route through.
      if (authState.status == AuthStatus.unknown) {
        return isPublicRoute ? null : AppRoutes.login;
      }

      final isAuthenticated = authState.isAuthenticated;

      // Unauthenticated → always redirect to login, regardless of target route.
      if (!isAuthenticated && !isPublicRoute) {
        return AppRoutes.login;
      }

      // Authenticated → don't let them sit on the login page.
      if (isAuthenticated && isPublicRoute) {
        return AppRoutes.home;
      }

      // No redirect needed.
      return null;
    },

    // ── Route Definitions ──────────────────────────────────────────────────
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const HomePage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Slide up like a modal
            const begin = Offset(0.0, 1.0);
            const end = Offset.zero;
            const curve = Curves.easeOutQuart;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.priceWatch,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const PriceWatchPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.scan,
        builder: (context, state) => const ScanPage(),
      ),
      GoRoute(
        path: AppRoutes.review,
        pageBuilder: (context, state) {
          final receipt = state.extra as Receipt;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ReviewPage(receipt: receipt),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              // Slide from right
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeOutExpo;
              var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(position: animation.drive(tween), child: child);
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.taxonomy,
        builder: (context, state) => const TaxonomySettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.integrations,
        builder: (context, state) => const IntegrationsPage(),
      ),
      GoRoute(
        path: AppRoutes.vault,
        builder: (context, state) => const VaultPage(),
      ),
      GoRoute(
        path: AppRoutes.modelManager,
        builder: (context, state) => const ModelManagerPage(),
      ),
      GoRoute(
        path: AppRoutes.boxes,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const BoxesPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeOutExpo;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.invoices,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const InvoicesPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeOutExpo;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
        ),
      ),
    ],
  );
});
