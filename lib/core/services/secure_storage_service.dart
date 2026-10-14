import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Centralized instance service for all sensitive data operations.
/// Uses the platform keychain/keystore via [FlutterSecureStorage].
class SecureStorageService {
  static const _hiveEncryptionKeyName = 'taidy_hive_encryption_key';
  static const _sqliteEncryptionKeyName = 'taidy_sqlite_encryption_key';

  final FlutterSecureStorage _storage;

  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  // ── Hive Encryption Key ─────────────────────────────────────────────────

  /// Whether a Hive encryption key is stored. Throws if secure storage itself
  /// cannot be read.
  Future<bool> hasHiveEncryptionKey() async {
    return await _storage.read(key: _hiveEncryptionKeyName) != null;
  }

  /// Returns a 256-bit encryption key for HiveAesCipher.
  /// Generates and persists one on first call.
  Future<Uint8List> getHiveEncryptionKey() async {
    final existing = await _storage.read(key: _hiveEncryptionKeyName);
    if (existing != null) {
      return base64Url.decode(existing);
    }
    // Generate a new 256-bit key (32 bytes)
    final key = Hive.generateSecureKey();
    final encoded = base64Url.encode(key);
    await _storage.write(key: _hiveEncryptionKeyName, value: encoded);
    debugPrint('SecureStorage: Generated new Hive encryption key.');
    return Uint8List.fromList(key);
  }

  /// Returns a 256-bit hexadecimal encryption key for SQLCipher/SQLite.
  /// Generates and persists one on first call.
  Future<String> getSqliteEncryptionKey() async {
    final existing = await _storage.read(key: _sqliteEncryptionKeyName);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final keyBytes = Hive.generateSecureKey();
    final hexKey = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: _sqliteEncryptionKeyName, value: hexKey);
    debugPrint('SecureStorage: Generated new SQLite encryption key.');
    return hexKey;
  }

  // ── Secret String Operations ────────────────────────────────────────────

  /// Read a secret value (API key, webhook secret, etc.).
  Future<String?> readSecret(String key) async {
    return await _storage.read(key: key);
  }

  /// Write a secret value to the platform keychain.
  Future<void> writeSecret(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Delete a secret.
  Future<void> deleteSecret(String key) async {
    await _storage.delete(key: key);
  }

  /// Check if a secret exists.
  Future<bool> hasSecret(String key) async {
    final val = await _storage.read(key: key);
    return val != null && val.isNotEmpty;
  }

  // ── Session & Auth Persistence ──────────────────────────────────────────

  /// Store the Supabase refresh token in secure storage.
  Future<void> saveRefreshToken(String token) async {
    await writeSecret(SecretKeys.supabaseRefreshToken, token);
  }

  /// Retrieve the stored Supabase refresh token.
  Future<String?> getRefreshToken() async {
    return await readSecret(SecretKeys.supabaseRefreshToken);
  }

  /// Delete the stored Supabase refresh token.
  Future<void> deleteRefreshToken() async {
    await deleteSecret(SecretKeys.supabaseRefreshToken);
  }

  /// Store the serialized Supabase session string.
  Future<void> savePersistedSession(String sessionJson) async {
    await writeSecret(SecretKeys.supabasePersistedSession, sessionJson);
  }

  /// Retrieve the persisted Supabase session string.
  Future<String?> getPersistedSession() async {
    return await readSecret(SecretKeys.supabasePersistedSession);
  }

  /// Delete the persisted Supabase session string.
  Future<void> deletePersistedSession() async {
    await deleteSecret(SecretKeys.supabasePersistedSession);
  }

  /// Record "Remember me" preference.
  Future<void> setRememberMe(bool enabled) async {
    await writeSecret(SecretKeys.rememberMe, enabled.toString());
  }

  /// Check whether "Remember me" is active. Defaults to true if unset.
  Future<bool> getRememberMe() async {
    final val = await readSecret(SecretKeys.rememberMe);
    if (val == null) return true;
    return val == 'true';
  }

  /// Purge all authentication and session data from secure storage.
  Future<void> purgeAuthData() async {
    await deleteRefreshToken();
    await deletePersistedSession();
  }

  /// Clear all secrets (nuclear option for clear-all-data).
  Future<void> clearAll() async {
    await _storage.deleteAll();
    debugPrint('SecureStorage: All secrets cleared.');
  }
}

// ── Well-Known Secret Keys ──────────────────────────────────────────────────
/// Constants for secret key names to avoid typos.
abstract class SecretKeys {
  static const geminiApiKey = 'gemini_api_key';
  static const webhookSecret = 'webhook_secret';
  static const webhookUrl = 'webhook_url';
  static const supabaseRefreshToken = 'supabase_refresh_token';
  static const supabasePersistedSession = 'supabase_persisted_session';
  static const rememberMe = 'auth_remember_me';
}

// ── Riverpod Provider ───────────────────────────────────────────────────────
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
