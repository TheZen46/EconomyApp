import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_storage_service.dart';

/// Persists the Supabase client session (access and refresh tokens) in the
/// platform keychain or keystore instead of supabase_flutter's default
/// SharedPreferences storage, which is plaintext on Android and desktop.
class SecureSessionStorage extends LocalStorage {
  /// Secure storage key of the session.
  static const String sessionKey = 'supabase_client_session';

  /// The SharedPreferences key under which earlier versions (the
  /// supabase_flutter default) stored the session. A session found there is
  /// moved into secure storage and the plaintext copy is deleted.
  final String? legacyPreferencesKey;

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;

  SecureSessionStorage({
    this.legacyPreferencesKey,
    @visibleForTesting Future<String?> Function(String key)? read,
    @visibleForTesting Future<void> Function(String key, String value)? write,
    @visibleForTesting Future<void> Function(String key)? delete,
  })  : _read = read ?? SecureStorageService.readSecret,
        _write = write ?? SecureStorageService.writeSecret,
        _delete = delete ?? SecureStorageService.deleteSecret;

  @override
  Future<void> initialize() async {
    final legacyKey = legacyPreferencesKey;
    if (legacyKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(legacyKey);
      if (legacy == null) return;
      if (await _read(sessionKey) == null) await _write(sessionKey, legacy);
      await prefs.remove(legacyKey);
    } catch (e) {
      debugPrint('SecureSessionStorage: could not migrate the stored session: $e');
    }
  }

  @override
  Future<bool> hasAccessToken() async => await _read(sessionKey) != null;

  @override
  Future<String?> accessToken() => _read(sessionKey);

  @override
  Future<void> removePersistedSession() => _delete(sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) => _write(sessionKey, persistSessionString);
}
