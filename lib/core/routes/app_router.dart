import '../../features/mileage/presentation/pages/mileage_page.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
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
import '../../features/reconciliation/presentation/pages/reconciliation_page.dart';
import '../../features/tax_compliance/presentation/pages/tax_compliance_hub_page.dart';
import '../../features/onboarding/presentation/pages/air_gapped_vault_onboarding_page.dart';
import '../../features/sync/presentation/pages/sync_progress_page.dart';
import '../../features/sync/presentation/providers/sync_provider.dart';

/// Centralized path constants for all declarative GoRouter application routes.
abstract class AppRoutes {
  /// Root entry route.
  static const root = '/';

  /// Authentication sign-in screen.
  static const login = '/login';

  /// Account registration screen.
  static const signup = '/signup';

  /// Initial or rehydration synchronization progress screen.
  static const syncProgress = '/sync_progress';

  /// Main financial dashboard and overview page.
  static const home = '/home';

  /// Application settings and cryptographic preferences page.
  static const settings = '/settings';

  /// Line-item price fluctuation tracking and analysis page.
  static const priceWatch = '/price_watch';

  /// Camera/Gallery receipt scanning view.
  static const scan = '/scan';

  /// Receipt extraction review and confirmation view.
  static const review = '/review';

  /// Category taxonomy customization view.
  static const taxonomy = '/taxonomy';

  /// Webhooks and external integrations settings view.
  static const integrations = '/integrations';

  /// Cryptographic vault and proof verification view.
  static const vault = '/vault';

  /// On-device AI model management and weights download view.
  static const modelManager = '/model_manager';

  /// Multi-box budget segregation management view.
  static const boxes = '/boxes';

  /// Invoicing and accounts receivable view.
  static const invoices = '/invoices';

  /// Bank CSV import and reconciliation view.
  static const reconciliation = '/reconciliation';

  /// Business travel mileage deduction tracker.
  static const mileage = '/mileage';

  /// Statutory tax compliance and quarterly deadlines hub.
  static const taxHub = '/tax_hub';

  /// Alias for tax compliance hub.
  static const taxCompliance = '/tax-compliance';

  /// Air-gapped biometric vault setup walkthrough.
  static const onboarding = '/onboarding';
}

/// The review screen. Exposed so that its handling of a missing receipt can be
/// tested without building the rest of the application.
final GoRoute reviewRoute = GoRoute(
  path: AppRoutes.review,
  // The receipt is passed in memory as `extra`, which GoRouter does not
  // keep across a browser reload, a deep link or state restoration.
  // Without it there is nothing to review, so go to the dashboard.
  redirect: (context, state) => state.extra is Receipt ? null : AppRoutes.home,
  pageBuilder: (context, state) {
    final receipt = state.extra! as Receipt;
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
);

/// Root navigation provider configuring the application's [GoRouter].
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:**
/// - `routerNotifierProvider`: Refreshes route guards upon auth changes.
/// - `authProvider`: Tracks active user authentication state.
/// - `authRepositoryProvider`: Checks current persistent session.
/// - `initialSyncCompletedProvider`: Directs new logins to sync progress before dashboard.
final routerProvider = Provider<GoRouter>((ref) {
  // RouterNotifier is a ChangeNotifier wired to authProvider and Supabase auth stream.
  // GoRouter calls refreshListenable.addListener so it re-runs redirect:
  // automatically on every auth event (signIn, signOut, tokenRefresh, expiry).
  final notifier = ref.read(routerNotifierProvider);

  // Determine the correct start location based on existing session or auth state.
  final hasSession = ref.read(authProvider).isAuthenticated ||
      ref.read(authRepositoryProvider).currentSession != null;

  return GoRouter(
    initialLocation: hasSession ? AppRoutes.home : AppRoutes.login,

    // Reactive refresh: every auth state event triggers a re-evaluation
    // of the redirect callback without needing a full app restart.
    refreshListenable: notifier,

    // ── Centralized Route Guard ─────────────────────────────────────────────
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final loc = state.matchedLocation;
      final isLoggingIn = loc == AppRoutes.login ||
          loc == AppRoutes.signup ||
          loc == AppRoutes.root;
      final isAuthenticated = authState.user != null || authState.isAuthenticated;
      final initialSyncDone = ref.read(initialSyncCompletedProvider);
      final isSyncing = loc == AppRoutes.syncProgress;

      // 1. Unauthenticated → redirect to /login and preserve deep-link target
      if (!isAuthenticated && !isLoggingIn) {
        final uri = state.uri.toString();
        if (uri.isNotEmpty &&
            uri != AppRoutes.root &&
            uri != AppRoutes.login &&
            uri != AppRoutes.signup &&
            uri != AppRoutes.syncProgress) {
          return '${AppRoutes.login}?from=${Uri.encodeComponent(uri)}';
        }
        return AppRoutes.login;
      }

      // 2. Authenticated but initial sync not yet completed → redirect to /sync_progress
      if (isAuthenticated && !initialSyncDone && !isSyncing) {
        final from = state.uri.queryParameters['from'];
        if (from != null && from.isNotEmpty) {
          return '${AppRoutes.syncProgress}?from=${Uri.encodeComponent(from)}';
        }
        final uri = state.uri.toString();
        if (uri.isNotEmpty &&
            uri != AppRoutes.root &&
            uri != AppRoutes.login &&
            uri != AppRoutes.signup &&
            uri != AppRoutes.syncProgress &&
            uri != AppRoutes.home) {
          return '${AppRoutes.syncProgress}?from=${Uri.encodeComponent(uri)}';
        }
        return AppRoutes.syncProgress;
      }

      // 3. Authenticated on login/signup/root/syncProgress when sync is completed → redirect to intended target or /home
      if (isAuthenticated && (isLoggingIn || (isSyncing && initialSyncDone))) {
        final from = state.uri.queryParameters['from'];
        if (from != null &&
            from.isNotEmpty &&
            from != AppRoutes.login &&
            from != AppRoutes.signup &&
            from != AppRoutes.root &&
            from != AppRoutes.syncProgress) {
          return from;
        }
        return AppRoutes.home;
      }

      // 4. Authenticated navigating to protected route → allow through
      return null;
    },

    // ── Route Definitions ──────────────────────────────────────────────────
    routes: [
      GoRoute(
        path: AppRoutes.root,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.syncProgress,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SyncProgressPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
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
      reviewRoute,
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
      GoRoute(
        path: AppRoutes.reconciliation,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ReconciliationPage(),
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
        path: AppRoutes.mileage,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MileagePage(),
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
        path: AppRoutes.taxHub,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const TaxComplianceHubPage(),
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
        path: AppRoutes.taxCompliance,
        redirect: (context, state) => AppRoutes.taxHub,
      ),
      GoRoute(
        path: '/tax_compliance',
        redirect: (context, state) => AppRoutes.taxHub,
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const AirGappedVaultOnboardingPage(),
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
