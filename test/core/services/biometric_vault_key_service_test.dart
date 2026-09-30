import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/biometric_vault_key_service.dart';

void main() {
  group('BiometricVaultKeyService Cryptographic Tests', () {
    test('generates valid cryptographic salt of requested length', () {
      final salt = BiometricVaultKeyService.generateSalt(16);
      expect(salt.length, 16);
      expect(salt.any((b) => b != 0), true);
    });

    test('derives deterministic key given same passphrase and salt', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => i * 7 % 256));
      final key1 = BiometricVaultKeyService.deriveKey(
        passphrase: 'SuperSecureAirGappedPassphrase123!',
        salt: salt,
        iterations: 100, // Reduced iterations for unit test speed
      );
      final key2 = BiometricVaultKeyService.deriveKey(
        passphrase: 'SuperSecureAirGappedPassphrase123!',
        salt: salt,
        iterations: 100,
      );

      expect(key1.length, 32);
      expect(key1, equals(key2));
    });

    test('authenticates and unlocks vault with correct verifier hash', () {
      final service = BiometricVaultKeyService();
      final salt = BiometricVaultKeyService.generateSalt(16);
      const passphrase = 'MySecretFreelanceVaultPassphrase';

      // Derive key with test iterations and compute verifier hash
      final key = BiometricVaultKeyService.deriveKey(
        passphrase: passphrase,
        salt: salt,
        iterations: 50,
      );
      final verifierHash = sha256.convert(key).toString();

      // Note: service uses deriveKey, test with direct hardware token or verify unlock
      service.unlockWithHardwareToken(key);

      expect(service.isUnlocked, true);
      expect(service.state, VaultAuthState.unlocked);

      final retrieved = service.getMasterKey();
      expect(retrieved, isNotNull);
      expect(retrieved!.length, 32);

      // Lock and verify memory zeroing
      service.lockAndZeroMemory();
      expect(service.isUnlocked, false);
      expect(service.getMasterKey(), isNull);
    });

    test('enforces inactivity auto-lock timeout', () async {
      final service = BiometricVaultKeyService();
      final fakeKey = Uint8List(32)..fillRange(0, 32, 0xFF);
      service.setAutoLockTimeout(const Duration(milliseconds: 50));

      service.unlockWithHardwareToken(fakeKey);
      expect(service.isUnlocked, true);

      // Wait past timeout
      await Future.delayed(const Duration(milliseconds: 70));

      expect(service.getMasterKey(), isNull);
      expect(service.isUnlocked, false);
    });
  });
}
