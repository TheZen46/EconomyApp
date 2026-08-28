import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/biometric_service.dart';

class BiometricGuard extends ConsumerStatefulWidget {
  final Widget? child;

  const BiometricGuard({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<BiometricGuard> createState() => _BiometricGuardState();
}

class _BiometricGuardState extends ConsumerState<BiometricGuard> with WidgetsBindingObserver {
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPrompt();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _handlePause();
    } else if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  void _handlePause() {
    final isBiometricEnabled = ref.read(biometricEnabledProvider);
    if (!isBiometricEnabled) return;
    if (mounted && _isAuthenticated) {
      setState(() {
        _isAuthenticated = false;
        _errorMessage = null;
      });
    }
  }

  void _handleResume() {
    final isBiometricEnabled = ref.read(biometricEnabledProvider);
    if (!isBiometricEnabled) return;
    if (mounted && !_isAuthenticated && !_isAuthenticating) {
      _authenticate();
    }
  }

  void _checkAndPrompt() {
    final isBiometricEnabled = ref.read(biometricEnabledProvider);
    if (isBiometricEnabled && !_isAuthenticated && !_isAuthenticating) {
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final biometricService = ref.read(biometricServiceProvider);
    final canAuth = await biometricService.canAuthenticate();

    if (!canAuth) {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
          // If device cannot authenticate, fall back to granting access or show warning
          _isAuthenticated = true;
        });
      }
      return;
    }

    final success = await biometricService.authenticate(
      'Authenticate with Fingerprint or Face ID to access tAIdy',
    );

    if (mounted) {
      setState(() {
        _isAuthenticating = false;
        _isAuthenticated = success;
        if (!success) {
          _errorMessage = 'Biometric authentication canceled or failed. Please try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBiometricEnabled = ref.watch(biometricEnabledProvider);

    if (!isBiometricEnabled || _isAuthenticated) {
      return widget.child ?? const SizedBox();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.primary.withOpacity(0.3), width: 2),
                    ),
                    child: Icon(
                      Icons.fingerprint_rounded,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'tAIdy Locked',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Biometric authentication is required to access your financial data.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 16, color: colorScheme.error),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(fontSize: 12, color: colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isAuthenticating ? null : _authenticate,
                      icon: _isAuthenticating
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.lock_open_rounded, size: 18),
                      label: Text(
                        _isAuthenticating ? 'Authenticating...' : 'Unlock with Biometrics',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
