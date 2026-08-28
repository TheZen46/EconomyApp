import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show AuthState;
import 'package:t_aidy/core/routes/app_router.dart';
import 'package:t_aidy/features/auth/domain/repositories/auth_repository.dart';
import 'package:t_aidy/features/auth/presentation/providers/auth_provider.dart';
import 'package:t_aidy/features/sync/presentation/providers/sync_provider.dart';
import 'package:t_aidy/features/sync/data/datasources/remote_replica_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/hive_receipt_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:dartz/dartz.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'dart:async';

class FakeAuthRepository implements AuthRepository {
  final StreamController<supabase.AuthState> _authStateController = StreamController<supabase.AuthState>.broadcast();
  User? user;
  Session? session;

  @override
  Stream<supabase.AuthState> get authStateChanges => _authStateController.stream;

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
    user = const User(id: 'auth-user', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-01-01');
    return Right(user);
  }

  @override
  Future<Either<AuthFailure, User?>> signUpWithEmailPassword(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    user = const User(id: 'auth-user', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-01-01');
    return Right(user);
  }

  @override
  Future<Either<AuthFailure, void>> signInWithGoogle({bool rememberMe = true}) async => const Right(null);

  @override
  Future<Either<AuthFailure, void>> signOut() async {
    user = null;
    session = null;
    return const Right(null);
  }

  @override
  Future<Either<AuthFailure, void>> resetPassword(String email) async => const Right(null);

  @override
  Future<Either<AuthFailure, User?>> recoverSession(String persistedSession) async {
    user = const User(id: 'auth-user', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-01-01');
    return Right(user);
  }

  @override
  Future<void> clearPersistedSession() async {
    user = null;
    session = null;
  }
}

class FakeRemoteReplicaDataSource implements RemoteReplicaDataSource {
  @override
  Future<List<RemoteFileEntry>> listRemoteFiles(String userId) async => [];

  @override
  Future<Uint8List> downloadFile(String path) async => Uint8List(0);

  @override
  Future<List<Map<String, dynamic>>> fetchReceipts(String userId) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchBoxes(String userId) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchAssets(String userId) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchInvoices(String userId) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchTaxonomies(String userId) async => [];
}

class FakeLocalReceiptDataSource implements LocalReceiptDataSource {
  @override
  Future<List<ReceiptModel>> getReceipts() async => [];

  @override
  Future<void> saveReceipt(ReceiptModel receipt) async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> deleteReceipt(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoRouter Centralized Guardrail Tests', () {
    testWidgets('unauthenticated user accessing /home is redirected to /login', (tester) async {
      final fakeRepo = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          authProvider.overrideWith((ref) => AuthNotifier(fakeRepo)),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.home);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, AppRoutes.login);
    });

    testWidgets('unauthenticated user accessing /vault is redirected to /login preserving target', (tester) async {
      final fakeRepo = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          authProvider.overrideWith((ref) => AuthNotifier(fakeRepo)),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.go('/vault');
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, AppRoutes.login);
      expect(router.state.uri.queryParameters['from'], '/vault');
    });

    testWidgets('unauthenticated user accessing protected sub-routes (/settings, /boxes, /invoices, /scan) is redirected to /login', (tester) async {
      final fakeRepo = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          authProvider.overrideWith((ref) => AuthNotifier(fakeRepo)),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final path in ['/settings', '/boxes', '/invoices', '/scan']) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(router.state.matchedLocation, AppRoutes.login);
        expect(router.state.uri.queryParameters['from'], path);
      }
    });

    testWidgets('authenticated user is redirected to /sync_progress preserving deep link until sync completes', (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authNotifier = AuthNotifier(fakeRepo);

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          authProvider.overrideWith((ref) => authNotifier),
          initialSyncCompletedProvider.overrideWith((ref) => false),
          remoteReplicaDataSourceProvider.overrideWithValue(FakeRemoteReplicaDataSource()),
          localDataSourceProvider.overrideWithValue(FakeLocalReceiptDataSource()),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Deep link to /vault while unauthenticated
      router.go('/vault');
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, AppRoutes.login);
      expect(router.state.uri.queryParameters['from'], '/vault');

      // Now authenticate -> blocks on /sync_progress preserving deep link
      await authNotifier.signInWithEmailPassword('user@taidy.io', 'Password123!');
      await tester.pump(const Duration(milliseconds: 200));

      expect(router.state.matchedLocation, AppRoutes.syncProgress);
      expect(router.state.uri.queryParameters['from'], '/vault');

      // Now complete sync
      container.read(initialSyncCompletedProvider.notifier).state = true;
      await tester.pump(const Duration(milliseconds: 200));

      expect(router.state.matchedLocation, AppRoutes.vault);

      // Drain remaining entrance delay timers
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
