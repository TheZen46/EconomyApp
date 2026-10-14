import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The initialized Supabase client, or null when `Supabase.initialize` did not
/// complete (invalid configuration, storage plugin failure, ...). The app then
/// runs local-only.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  try {
    return Supabase.instance.client;
  } catch (_) {
    // Supabase.instance asserts, and client is unset, before initialization.
    return null;
  }
});

/// The Supabase client for data sources that need a non-null client: the
/// initialized one, or [offlineSupabaseClient] when there is none, whose
/// requests fail like requests made without a network connection.
final supabaseClientOrOfflineProvider = Provider<SupabaseClient>((ref) {
  return ref.watch(supabaseClientProvider) ?? offlineSupabaseClient;
});

/// A client for a host that never resolves (RFC 2606 reserves `.invalid`),
/// with token refresh disabled. Every request fails with a network error,
/// which the data sources already handle as being offline.
final SupabaseClient offlineSupabaseClient = SupabaseClient(
  'https://offline.invalid',
  'offline',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

/// Whether [url] can be passed to `Supabase.initialize`: an absolute http(s)
/// URL with a host.
bool isValidSupabaseUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
}
