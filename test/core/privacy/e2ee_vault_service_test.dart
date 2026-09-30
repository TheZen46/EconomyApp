import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/privacy/e2ee_vault_service.dart';

void main() {
  group('E2eeVaultService Tests', () {
    const testSecretPayload = '{"receipt_id": "rec-12345", "amount": 1250.75, "merchant": "Apple Store"}';
    const masterPassphrase = 'SuperSecretFreelancerMasterKey!2026';
    const wrongPassphrase = 'WrongMasterKeyAttempt';

    test('encrypts and decrypts payload cleanly with correct master passphrase', () {
      final envelope = E2eeVaultService.encrypt(
        data: testSecretPayload,
        passphrase: masterPassphrase,
      );

      expect(envelope.ciphertextBase64.isNotEmpty, true);
      expect(envelope.saltBase64.isNotEmpty, true);
      expect(envelope.ivBase64.isNotEmpty, true);
      expect(envelope.tagBase64.isNotEmpty, true);
      expect(envelope.ciphertextBase64, isNot(contains('Apple Store')));

      final decrypted = E2eeVaultService.decrypt(
        envelope: envelope,
        passphrase: masterPassphrase,
      );

      expect(decrypted, testSecretPayload);
    });

    test('fails decryption and throws when incorrect passphrase is provided', () {
      final envelope = E2eeVaultService.encrypt(
        data: testSecretPayload,
        passphrase: masterPassphrase,
      );

      expect(
        () => E2eeVaultService.decrypt(envelope: envelope, passphrase: wrongPassphrase),
        throwsStateError,
      );
    });

    test('serializes and deserializes envelope JSON safely', () {
      final envelope = E2eeVaultService.encrypt(
        data: testSecretPayload,
        passphrase: masterPassphrase,
      );

      final jsonStr = envelope.serialize();
      final revived = EncryptedEnvelope.deserialize(jsonStr);

      final decrypted = E2eeVaultService.decrypt(
        envelope: revived,
        passphrase: masterPassphrase,
      );

      expect(decrypted, testSecretPayload);
    });
  });
}
