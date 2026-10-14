import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/providers/storage_providers.dart';
import 'package:t_aidy/core/providers/supabase_providers.dart';
import 'package:t_aidy/core/services/google_drive_service.dart';
import 'package:t_aidy/core/services/secure_storage_service.dart';
import 'package:t_aidy/core/services/telemetry_service.dart';
import 'package:t_aidy/core/sync/sync_providers.dart';
import 'package:t_aidy/features/auth/presentation/providers/auth_provider.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/settings/presentation/providers/llm_provider.dart';
import 'package:t_aidy/features/settings/presentation/providers/taxonomy_provider.dart';

import 'package:hive/hive.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/sync_item_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

class _FakeSecureStorageService extends Fake implements SecureStorageService {}
class _FakeGoogleDriveService extends Fake implements GoogleDriveService {}
class _FakeTelemetryService extends Fake implements TelemetryService {}
class _FakeBox<T> extends Fake implements Box<T> {
  @override
  bool get isEmpty => true;

  @override
  bool get isNotEmpty => false;

  @override
  Iterable<T> get values => const [];

  @override
  Stream<BoxEvent> watch({dynamic key}) => const Stream.empty();

  @override
  T? get(dynamic key, {T? defaultValue}) => defaultValue;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ProviderContainer DI Contract Tests', () {
    test('required box providers throw UnimplementedError when unprovided', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(settingsBoxProvider), throwsA(isA<UnimplementedError>()));
      expect(() => container.read(hiveBoxProvider), throwsA(isA<UnimplementedError>()));
      expect(() => container.read(boxesHiveBoxProvider), throwsA(isA<UnimplementedError>()));
      expect(() => container.read(invoicesHiveBoxProvider), throwsA(isA<UnimplementedError>()));
      expect(() => container.read(assetsBoxProvider), throwsA(isA<UnimplementedError>()));
      expect(() => container.read(taxonomyBoxProvider), throwsA(isA<UnimplementedError>()));
      expect(() => container.read(outboxHiveBoxProvider), throwsA(isA<UnimplementedError>()));
      expect(() => container.read(outboxServiceProvider), throwsA(isA<UnimplementedError>()));
    });

    test('typed nullable companion providers return null safely without throwing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(settingsBoxNullableProvider), isNull);
      expect(container.read(receiptsBoxNullableProvider), isNull);
      expect(container.read(boxesBoxNullableProvider), isNull);
      expect(container.read(invoicesBoxNullableProvider), isNull);
      expect(container.read(assetsBoxNullableProvider), isNull);
      expect(container.read(taxonomyBoxNullableProvider), isNull);
      expect(container.read(outboxHiveBoxNullableProvider), isNull);
      expect(container.read(outboxServiceNullableProvider), isNull);
    });

    test('syncManagerProvider fails fast when Supabase is present but box overrides are missing', () {
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(offlineSupabaseClient),
        ],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(syncManagerProvider),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('services can be substituted via Riverpod overrides without platform channel dependencies', () {
      final fakeSecureStorage = _FakeSecureStorageService();
      final fakeDrive = _FakeGoogleDriveService();
      final fakeTelemetry = _FakeTelemetryService();
      final fakeSyncBox = _FakeBox<SyncItemModel>();
      final fakeReceiptsBox = _FakeBox<ReceiptModel>();
      final fakeSettingsBox = _FakeBox<dynamic>();

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(fakeSecureStorage),
          googleDriveServiceProvider.overrideWithValue(fakeDrive),
          telemetryServiceProvider.overrideWithValue(fakeTelemetry),
          syncBoxProvider.overrideWithValue(fakeSyncBox),
          hiveBoxProvider.overrideWithValue(fakeReceiptsBox),
          settingsBoxProvider.overrideWithValue(fakeSettingsBox),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(secureStorageProvider), same(fakeSecureStorage));
      expect(container.read(googleDriveServiceProvider), same(fakeDrive));
      expect(container.read(telemetryServiceProvider), same(fakeTelemetry));

      // Dependent services resolve substituted instances cleanly
      expect(() => container.read(authRepositoryProvider), returnsNormally);
      expect(() => container.read(syncServiceProvider), returnsNormally);
      expect(() => container.read(vlmEngineServiceProvider), returnsNormally);
    });
  });
}
