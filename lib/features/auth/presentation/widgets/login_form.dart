import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

/// Form component for user sign in and account registration with strong client-side validation.
class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  bool _isSignUpMode = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;

  /// RFC 5322 compliant email regular expression
  static final RegExp _rfc5322EmailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );

  static final RegExp _hasNumberRegex = RegExp(r'\d');
  static final RegExp _hasSpecialCharRegex = RegExp(r'[!@#$%^&*(),.?":{}|<>\-_=+/\\~`\[\]]');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final trimmed = value.trim();
    if (!_rfc5322EmailRegex.hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!_hasNumberRegex.hasMatch(value)) {
      return 'Password must contain at least 1 number';
    }
    if (!_hasSpecialCharRegex.hasMatch(value)) {
      return 'Password must contain at least 1 special character';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final notifier = ref.read(authProvider.notifier);

    if (_isSignUpMode) {
      await notifier.signUp(email: email, password: password, rememberMe: _rememberMe);
    } else {
      await notifier.signInWithEmailPassword(email, password, rememberMe: _rememberMe);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    final emailError = _validateEmail(email);
    if (emailError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(email.isEmpty ? 'Enter your email address first.' : 'Enter a valid email address first.'),
          backgroundColor: AppColors.destructive,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await ref.read(authProvider.notifier).resetPassword(email);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final fg = isDark ? AppColors.darkFg : AppColors.lightFg;
    final muted = isDark ? AppColors.darkFgDim : AppColors.lightMuted;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // -- Mode toggle (Sign In / Sign Up) -----------------------
            Row(
              children: [
                _ModeTab(
                  label: 'Sign In',
                  isActive: !_isSignUpMode,
                  fg: fg,
                  muted: muted,
                  onTap: () {
                    if (_isSignUpMode) {
                      setState(() {
                        _isSignUpMode = false;
                        _formKey.currentState?.reset();
                      });
                    }
                  },
                ),
                const SizedBox(width: 16),
                _ModeTab(
                  label: 'Sign Up',
                  isActive: _isSignUpMode,
                  fg: fg,
                  muted: muted,
                  onTap: () {
                    if (!_isSignUpMode) {
                      setState(() {
                        _isSignUpMode = true;
                        _formKey.currentState?.reset();
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // -- Email Input Field -------------------------------------
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              enabled: !authState.isLoading,
              style: GoogleFonts.spaceGrotesk(color: fg),
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'name@example.com',
                prefixIcon: Icon(Icons.email_outlined, color: muted, size: 20),
              ),
              validator: _validateEmail,
            ),
            const SizedBox(height: 16),

            // -- Password Input Field ----------------------------------
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              enabled: !authState.isLoading,
              onFieldSubmitted: (_) => _submit(),
              style: GoogleFonts.spaceGrotesk(color: fg),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outlined, color: muted, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: muted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: _validatePassword,
            ),

            const SizedBox(height: 12),

            // -- Remember me & Forgot password row ---------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: InkWell(
                    onTap: authState.isLoading
                        ? null
                        : () => setState(() => _rememberMe = !_rememberMe),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: Checkbox(
                            value: _rememberMe,
                            onChanged: authState.isLoading
                                ? null
                                : (val) => setState(() => _rememberMe = val ?? true),
                            activeColor: AppColors.accent,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Remember me',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              color: fg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_isSignUpMode)
                  TextButton(
                    onPressed: authState.isLoading ? null : _forgotPassword,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Forgot password?',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // -- Submit Button -----------------------------------------
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: authState.isLoading ? null : _submit,
                child: authState.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isSignUpMode ? 'Create Account' : 'Sign In',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Mode Tab Widget ----------------------------------------------------------
class _ModeTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color fg;
  final Color muted;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.isActive,
    required this.fg,
    required this.muted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 15,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w300,
              color: isActive ? fg : muted,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2,
            width: isActive ? 40 : 0,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}
