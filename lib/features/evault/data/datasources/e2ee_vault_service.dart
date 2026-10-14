import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Structured envelope containing an encrypted payload and associated cryptographic metadata.
class EncryptedEnvelope {
  final int version;
  final String saltBase64;
  final String ivBase64;
  final String ciphertextBase64;
  final String tagBase64;

  const EncryptedEnvelope({
    this.version = 1,
    required this.saltBase64,
    required this.ivBase64,
    required this.ciphertextBase64,
    required this.tagBase64,
  });

  Map<String, dynamic> toJson() => {
        'v': version,
        'salt': saltBase64,
        'iv': ivBase64,
        'ct': ciphertextBase64,
        'tag': tagBase64,
      };

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) => EncryptedEnvelope(
        version: json['v'] as int? ?? 1,
        saltBase64: json['salt'] as String,
        ivBase64: json['iv'] as String,
        ciphertextBase64: json['ct'] as String,
        tagBase64: json['tag'] as String,
      );

  String serialize() => jsonEncode(toJson());

  factory EncryptedEnvelope.deserialize(String raw) =>
      EncryptedEnvelope.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// Zero-Knowledge End-to-End Encryption Service for local-first CRDT vaults.
class E2eeVaultService {
  static const int kSaltLength = 16;
  static const int kIvLength = 12;
  static const int kKeyLength = 32; // 256-bit AES
  static const int kPbkdf2Iterations = 10000;

  /// Derives a 256-bit symmetric encryption key from [passphrase] and [salt] using PBKDF2-HMAC-SHA256.
  static Uint8List deriveKey({
    required String passphrase,
    required Uint8List salt,
    int iterations = kPbkdf2Iterations,
  }) {
    final passBytes = utf8.encode(passphrase);
    var hmac = Hmac(sha256, passBytes);

    // Initial block U_1 = HMAC(passphrase, salt || 0x00000001)
    final initialData = Uint8List(salt.length + 4);
    initialData.setRange(0, salt.length, salt);
    initialData[salt.length] = 0;
    initialData[salt.length + 1] = 0;
    initialData[salt.length + 2] = 0;
    initialData[salt.length + 3] = 1;

    var u = hmac.convert(initialData).bytes;
    var result = List<int>.from(u);

    // Subsequent iterations: U_i = HMAC(passphrase, U_{i-1})
    for (int i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (int k = 0; k < result.length; k++) {
        result[k] ^= u[k];
      }
    }

    return Uint8List.fromList(result.sublist(0, kKeyLength));
  }

  /// Encrypts plaintext [data] using derived key and returns an [EncryptedEnvelope].
  static EncryptedEnvelope encrypt({
    required String data,
    required String passphrase,
  }) {
    final rand = Random.secure();
    final salt = Uint8List(kSaltLength);
    final iv = Uint8List(kIvLength);
    for (int i = 0; i < kSaltLength; i++) {
      salt[i] = rand.nextInt(256);
    }
    for (int i = 0; i < kIvLength; i++) {
      iv[i] = rand.nextInt(256);
    }

    final key = deriveKey(passphrase: passphrase, salt: salt);
    final plaintextBytes = utf8.encode(data);

    // CTR-based stream cipher with HMAC integrity tag (AES-GCM functional emulation)
    final ciphertext = _applyKeystream(plaintextBytes, key, iv);
    final hmac = Hmac(sha256, key);
    final tag = hmac.convert(ciphertext).bytes;

    return EncryptedEnvelope(
      saltBase64: base64Encode(salt),
      ivBase64: base64Encode(iv),
      ciphertextBase64: base64Encode(ciphertext),
      tagBase64: base64Encode(tag),
    );
  }

  /// Decrypts an [EncryptedEnvelope] using [passphrase]. Throws [SecurityException] on invalid key or corrupted tag.
  static String decrypt({
    required EncryptedEnvelope envelope,
    required String passphrase,
  }) {
    final salt = base64Decode(envelope.saltBase64);
    final iv = base64Decode(envelope.ivBase64);
    final ciphertext = base64Decode(envelope.ciphertextBase64);
    final expectedTag = base64Decode(envelope.tagBase64);

    final key = deriveKey(passphrase: passphrase, salt: salt);

    // Verify tag integrity before decryption
    final hmac = Hmac(sha256, key);
    final computedTag = hmac.convert(ciphertext).bytes;

    if (!_constantTimeEquals(computedTag, expectedTag)) {
      throw StateError('Authentication tag mismatch: invalid passphrase or corrupted ciphertext');
    }

    final decryptedBytes = _applyKeystream(ciphertext, key, iv);
    return utf8.decode(decryptedBytes);
  }

  static Uint8List _applyKeystream(List<int> input, Uint8List key, Uint8List iv) {
    final output = Uint8List(input.length);
    final hmac = Hmac(sha256, key);

    int blockIndex = 0;
    for (int i = 0; i < input.length; i += 32) {
      final counterData = Uint8List(iv.length + 4);
      counterData.setRange(0, iv.length, iv);
      counterData[iv.length] = (blockIndex >> 24) & 0xFF;
      counterData[iv.length + 1] = (blockIndex >> 16) & 0xFF;
      counterData[iv.length + 2] = (blockIndex >> 8) & 0xFF;
      counterData[iv.length + 3] = blockIndex & 0xFF;

      final keystreamBlock = hmac.convert(counterData).bytes;
      final chunkSize = min(32, input.length - i);

      for (int j = 0; j < chunkSize; j++) {
        output[i + j] = input[i + j] ^ keystreamBlock[j];
      }
      blockIndex++;
    }

    return output;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
