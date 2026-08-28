import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';
import '../../features/receipt_scanning/presentation/providers/receipt_provider.dart';

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final biometricEnabledProvider = StateNotifierProvider<BiometricEnabledNotifier, bool>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return BiometricEnabledNotifier(box);
  } catch (_) {
    return BiometricEnabledNotifier(null);
  }
});

class BiometricEnabledNotifier extends StateNotifier<bool> {
  final Box? _box;
  static const _key = 'biometric_auth_enabled';

  BiometricEnabledNotifier([this._box])
      : super(_box?.get(_key, defaultValue: false) as bool? ?? false);

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _box?.put(_key, enabled);
  }

  Future<void> toggle() async {
    await setEnabled(!state);
  }
}

class BiometricService {
  final LocalAuthentication _localAuth;

  BiometricService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (e) {
      debugPrint('BiometricService.canAuthenticate error: $e');
      return false;
    }
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('BiometricService.authenticate error: $e');
      return false;
    }
  }
}
