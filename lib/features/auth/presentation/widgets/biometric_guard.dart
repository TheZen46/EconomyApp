import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/biometric_service.dart';

class BiometricGuard extends ConsumerStatefulWidget {
  final Widget? child;
  final Duration inactivityDuration;

  const BiometricGuard({
    super.key,
    required this.child,
    this.inactivityDuration = const Duration(minutes: 5),
  });

  @override
  ConsumerState<BiometricGuard> createState() => _BiometricGuardState();
}

class _BiometricGuardState extends ConsumerState<BiometricGuard> with WidgetsBindingObserver {
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  bool _isTimedOut = false;
  String? _errorMessage;
  Timer? _inactivityTimer;

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
    _inactivityTimer?.cancel();
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

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    final isBiometricEnabled = ref.read(biometricEnabledProvider);
    if (!isBiometricEnabled || !_isAuthenticated) return;

    _inactivityTimer = Timer(widget.inactivityDuration, () {
      if (mounted && _isAuthenticated) {
        setState(() {
          _isAuthenticated = false;
          _isTimedOut = true;
          _errorMessage = null;
        });
      }
    });
  }

  void _handlePause() {
    _inactivityTimer?.cancel();
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
      // Fail closed: being unable to verify the user is not a successful verification.
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
          _errorMessage = 'This device has no biometrics or screen lock available, so tAIdy cannot '
              'verify you. Set up a screen lock in your device settings, then try again.';
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
        if (success) {
          _isTimedOut = false;
          _resetInactivityTimer();
        } else {
          _errorMessage = 'Biometric authentication canceled or failed. Please try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBiometricEnabled = ref.watch(biometricEnabledProvider);
    final isLocked = isBiometricEnabled && !_isAuthenticated;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetInactivityTimer(),
        onPointerMove: (_) => _resetInactivityTimer(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Preserves active form state and in-memory heap in encrypted RAM
            if (widget.child != null)
              Offstage(
                offstage: isLocked,
                child: widget.child!,
              ),
            // Minimal in-place security veil
            if (isLocked)
              _buildLockVeil(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLockVeil(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF334155)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3), width: 1.5),
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      size: 38,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'tAIdy Locked',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isTimedOut
                        ? '5-minute session timeout. Unsaved form state securely preserved in encrypted RAM.'
                        : 'Biometric authentication is required to access your financial data.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF94A3B8),
                      height: 1.4,
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 16, color: Color(0xFFF87171)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFF87171)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF38BDF8),
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isAuthenticating ? null : _authenticate,
                      icon: _isAuthenticating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0F172A),
                              ),
                            )
                          : const Icon(Icons.lock_open_rounded, size: 18),
                      label: Text(
                        _isAuthenticating ? 'Authenticating...' : 'Unlock with Biometrics',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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
