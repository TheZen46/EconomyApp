import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart'; // Import added for future real auth, not used yet
import '../../../../core/theme/app_theme.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    if (_usernameController.text == 'developer' && _passwordController.text == '1') {
      if (_rememberMe) {
        final box = ref.read(settingsBoxProvider);
        box.put('isLoggedIn', true);
      }
      if (mounted) {
        context.go('/home');
      }
    } else {
      if (mounted) {
        setState(() {
          _error = 'Invalid credentials';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.background, AppTheme.surface],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_long, size: 64, color: AppTheme.primary),
                const SizedBox(height: 16),
                Text(
                  'tAIdy',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                ),
                Text(
                  'Expense Tracker',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.textDim,
                  ),
                ),
                const SizedBox(height: 48),

                // Username
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixIcon: const Icon(Icons.person),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 16),

                // Password
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 16),

                // Remember Me
                Consumer(
                  builder: (context, ref, child) {
                    return CheckboxListTile(
                      value: _rememberMe,
                      onChanged: (val) => setState(() => _rememberMe = val ?? false),
                      title: const Text('Remember me on this device'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppTheme.primary,
                      checkColor: AppTheme.background,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background),
                          )
                        : const Text('Login'),
                  ),
                ),
                
                const SizedBox(height: 24),
                Text(
                  'Dev Credentials: developer / 1',
                  style: TextStyle(color: AppTheme.textDim.withOpacity(0.5), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
