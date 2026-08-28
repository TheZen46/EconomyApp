import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Centralized service for all sensitive data operations.
/// Uses the platform keychain/keystore via flutter_secure_storage.
class SecureStorageService {
  static const _hiveEncryptionKeyName = 'taidy_hive_encryption_key';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  // ── Hive Encryption Key ─────────────────────────────────────────────────

  /// Returns a 256-bit encryption key for HiveAesCipher.
  /// Generates and persists one on first call.
  static Future<Uint8List> getHiveEncryptionKey() async {
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

  // ── Secret String Operations ────────────────────────────────────────────

  /// Read a secret value (API key, webhook secret, etc.).
  static Future<String?> readSecret(String key) async {
    return await _storage.read(key: key);
  }

  /// Write a secret value to the platform keychain.
  static Future<void> writeSecret(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Delete a secret.
  static Future<void> deleteSecret(String key) async {
    await _storage.delete(key: key);
  }

  /// Check if a secret exists.
  static Future<bool> hasSecret(String key) async {
    final val = await _storage.read(key: key);
    return val != null && val.isNotEmpty;
  }

  // ── Session & Auth Persistence ──────────────────────────────────────────

  /// Store the Supabase refresh token in secure storage.
  static Future<void> saveRefreshToken(String token) async {
    await writeSecret(SecretKeys.supabaseRefreshToken, token);
  }

  /// Retrieve the stored Supabase refresh token.
  static Future<String?> getRefreshToken() async {
    return await readSecret(SecretKeys.supabaseRefreshToken);
  }

  /// Delete the stored Supabase refresh token.
  static Future<void> deleteRefreshToken() async {
    await deleteSecret(SecretKeys.supabaseRefreshToken);
  }

  /// Store the serialized Supabase session string.
  static Future<void> savePersistedSession(String sessionJson) async {
    await writeSecret(SecretKeys.supabasePersistedSession, sessionJson);
  }

  /// Retrieve the persisted Supabase session string.
  static Future<String?> getPersistedSession() async {
    return await readSecret(SecretKeys.supabasePersistedSession);
  }

  /// Delete the persisted Supabase session string.
  static Future<void> deletePersistedSession() async {
    await deleteSecret(SecretKeys.supabasePersistedSession);
  }

  /// Record "Remember me" preference.
  static Future<void> setRememberMe(bool enabled) async {
    await writeSecret(SecretKeys.rememberMe, enabled.toString());
  }

  /// Check whether "Remember me" is active. Defaults to true if unset.
  static Future<bool> getRememberMe() async {
    final val = await readSecret(SecretKeys.rememberMe);
    if (val == null) return true;
    return val == 'true';
  }

  /// Purge all authentication and session data from secure storage.
  static Future<void> purgeAuthData() async {
    await deleteRefreshToken();
    await deletePersistedSession();
  }

  /// Clear all secrets (nuclear option for clear-all-data).
  static Future<void> clearAll() async {
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
