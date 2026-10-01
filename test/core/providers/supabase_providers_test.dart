import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/providers/supabase_providers.dart';
import 'package:t_aidy/core/sync/sync_providers.dart';
import 'package:t_aidy/features/auth/presentation/providers/auth_provider.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/sync/presentation/providers/sync_provider.dart';

void main() {
  group('without an initialized Supabase client', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('the client provider is null and data sources use the offline client', () {
      expect(container.read(supabaseClientProvider), isNull);
      expect(container.read(supabaseClientOrOfflineProvider), same(offlineSupabaseClient));
    });

    test('cloud-dependent providers can be read instead of throwing', () {
      expect(() => container.read(supabaseDataSourceProvider), returnsNormally);
      expect(() => container.read(modelRepositoryProvider), returnsNormally);
      expect(() => container.read(remoteReplicaDataSourceProvider), returnsNormally);
      expect(container.read(authRepositoryProvider).currentUser, isNull);
      expect(container.read(syncManagerProvider), isNull);
    });
  });

  test('isValidSupabaseUrl accepts only absolute http(s) URLs', () {
    expect(isValidSupabaseUrl('https://abc.supabase.co'), isTrue);
    expect(isValidSupabaseUrl('http://localhost:54321'), isTrue);
    expect(isValidSupabaseUrl(''), isFalse);
    expect(isValidSupabaseUrl('abc.supabase.co'), isFalse);
    expect(isValidSupabaseUrl('https://'), isFalse);
    expect(isValidSupabaseUrl('ftp://abc.supabase.co'), isFalse);
  });
}
