// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/receipt_scanning/presentation/providers/receipt_provider.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  final settingsBox = ref.watch(settingsBoxProvider);
  final isLoggedIn = settingsBox.get('isLoggedIn', defaultValue: false);

  return GoRouter(
    initialLocation: isLoggedIn ? '/home' : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const HomePage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/settings',
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
        path: '/price_watch',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const PriceWatchPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
             return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanPage(),
      ),
      GoRoute(
        path: '/review',
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
        path: '/taxonomy',
        builder: (context, state) => const TaxonomySettingsPage(),
      ),
      GoRoute(
        path: '/integrations',
        builder: (context, state) => const IntegrationsPage(),
      ),
      GoRoute(
        path: '/vault',
        builder: (context, state) => const VaultPage(),
      ),
      GoRoute(
        path: '/model_manager',
        builder: (context, state) => const ModelManagerPage(),
      ),
      GoRoute(
        path: '/boxes',
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
        path: '/invoices',
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
