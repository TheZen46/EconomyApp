import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Key derivation and vault authentication status.
enum VaultAuthState {
  locked,
  unlocked,
  biometricPending,
  uninitialized,
}

/// [UNIQUE] Biometric Master Key Derivation & Ephemeral Memory Erasure Service.
///
/// Implements PBKDF2-HMAC-SHA256 high-iteration key stretching (100,000 rounds)
/// with automatic inactivity timeout and deterministic in-memory key byte zeroing.
class BiometricVaultKeyService {
  static const int pbkdf2Iterations = 100000;
  static const int keyLengthBytes = 32; // 256 bits

  Uint8List? _ephemeralMasterKey;
  DateTime? _lastActivityTime;
  Duration _autoLockDuration = const Duration(minutes: 5);
  VaultAuthState _state = VaultAuthState.locked;

  VaultAuthState get state => _state;
  bool get isUnlocked => _state == VaultAuthState.unlocked && _ephemeralMasterKey != null;

  /// Sets auto-lock duration
  void setAutoLockTimeout(Duration duration) {
    _autoLockDuration = duration;
  }

  /// Cryptographically derives a 256-bit symmetric encryption key from a passphrase and salt.
  static Uint8List deriveKey({
    required String passphrase,
    required Uint8List salt,
    int iterations = pbkdf2Iterations,
  }) {
    if (salt.length < 16) {
      throw ArgumentError('Salt must be at least 16 bytes for cryptographic security.');
    }

    final passphraseBytes = utf8.encode(passphrase);
    var derivedKey = Uint8List(keyLengthBytes);

    // PBKDF2-HMAC-SHA256 block calculation
    var u = Hmac(sha256, passphraseBytes).convert([...salt, 0, 0, 0, 1]).bytes;
    var xorSum = List<int>.from(u);

    for (int i = 1; i < iterations; i++) {
      u = Hmac(sha256, passphraseBytes).convert(u).bytes;
      for (int k = 0; k < xorSum.length; k++) {
        xorSum[k] ^= u[k];
      }
    }

    final sub = xorSum.sublist(0, min(keyLengthBytes, xorSum.length));
    derivedKey.setRange(0, sub.length, sub);
    return derivedKey;
  }

  /// Generates a cryptographically random 16-byte salt
  static Uint8List generateSalt([int length = 16]) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// Unlocks the vault in memory using the supplied passphrase and salt.
  bool unlockWithPassphrase({
    required String passphrase,
    required Uint8List salt,
    required String expectedKeyVerifierHash,
  }) {
    final key = deriveKey(passphrase: passphrase, salt: salt);
    final keyHash = sha256.convert(key).toString();

    if (keyHash == expectedKeyVerifierHash) {
      _ephemeralMasterKey = key;
      _lastActivityTime = DateTime.now();
      _state = VaultAuthState.unlocked;
      return true;
    } else {
      // Zero out candidate key immediately
      key.fillRange(0, key.length, 0);
      return false;
    }
  }

  /// Direct unlock when authenticated via hardware biometric enclave token
  void unlockWithHardwareToken(Uint8List hardwareMasterKey) {
    _ephemeralMasterKey = Uint8List.fromList(hardwareMasterKey);
    _lastActivityTime = DateTime.now();
    _state = VaultAuthState.unlocked;
  }

  /// Accesses the ephemeral master key and refreshes inactivity timer.
  Uint8List? getMasterKey() {
    if (!isUnlocked) return null;

    // Check inactivity timeout
    if (_lastActivityTime != null && DateTime.now().difference(_lastActivityTime!) > _autoLockDuration) {
      lockAndZeroMemory();
      return null;
    }

    _lastActivityTime = DateTime.now();
    return _ephemeralMasterKey;
  }

  /// Cryptographically zeroes out in-memory key bytes upon vault lock.
  void lockAndZeroMemory() {
    if (_ephemeralMasterKey != null) {
      _ephemeralMasterKey!.fillRange(0, _ephemeralMasterKey!.length, 0);
      _ephemeralMasterKey = null;
    }
    _lastActivityTime = null;
    _state = VaultAuthState.locked;
  }
}
