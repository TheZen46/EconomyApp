// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';

class IntegrationsPage extends ConsumerStatefulWidget {
  const IntegrationsPage({super.key});

  @override
  ConsumerState<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends ConsumerState<IntegrationsPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  bool _isEnabled = false;
  bool _isLoading = false;

  late Box _settingsBox;

  @override
  void initState() {
    super.initState();
    // Defer loading to allow provider access
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  void _loadSettings() {
    _settingsBox = ref.read(settingsBoxProvider);
    setState(() {
      _urlController.text = _settingsBox.get('webhook_url', defaultValue: '');
      _secretController.text = _settingsBox.get('webhook_secret', defaultValue: '');
      _isEnabled = _settingsBox.get('webhook_enabled', defaultValue: false);
    });
  }

  Future<void> _save() async {
    await _settingsBox.put('webhook_url', _urlController.text.trim());
    await _settingsBox.put('webhook_secret', _secretController.text.trim());
    await _settingsBox.put('webhook_enabled', _isEnabled);
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Integration settings saved')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isLoading = true);
    try {
      // Temporarily save to ensure service uses latest values
      await _settingsBox.put('webhook_url', _urlController.text.trim());
      await _settingsBox.put('webhook_secret', _secretController.text.trim());
      await _settingsBox.put('webhook_enabled', _isEnabled); // Must be enabled usually? Service check logic depends on this.

      final service = ref.read(webhookServiceProvider);
      // Force enabled for test? Service checks 'webhook_enabled'. Let's enforce enable for test or warn.
      if (!_isEnabled) { 
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enable integration to test')));
         return;
      }

      await service.sendTestEvent();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Success', style: TextStyle(color: Colors.green)),
            content: const Text('Test event sent successfully! Check your endpoint.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
            backgroundColor: AppTheme.surface,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Connection Failed', style: TextStyle(color: AppTheme.error)),
            content: Text(e.toString()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
             backgroundColor: AppTheme.surface,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Integrations & Webhooks'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The Connector',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 8),
            const Text(
              'Automatically push your receipt data to external systems like Home Assistant, Zapier, or your own server.',
              style: TextStyle(color: AppTheme.textDim),
            ),
            const SizedBox(height: 32),

            // Toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Webhook', style: TextStyle(color: AppTheme.textMain)),
              subtitle: const Text('POST JSON payload on new receipt', style: TextStyle(color: AppTheme.textDim)),
              value: _isEnabled,
              activeThumbColor: AppTheme.primary,
              onChanged: (val) {
                setState(() => _isEnabled = val);
                _save();
              },
            ),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),

            // URL Input
            const Text('Payload URL', style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              style: const TextStyle(color: AppTheme.textMain),
              decoration: InputDecoration(
                hintText: 'https://hooks.zapier.com/...',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withAlpha(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: 24),

            // Secret Input
            const Text('Secret Token (Optional)', style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _secretController,
              obscureText: true,
              style: const TextStyle(color: AppTheme.textMain),
              decoration: InputDecoration(
                hintText: 'Sent in X-Auth-Secret header',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withAlpha(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (_) => _save(),
            ),

            const SizedBox(height: 48),

            // Test Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _testConnection,
                icon: _isLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.bolt),
                label: const Text('Send Test Event'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surface,
                  foregroundColor: _isEnabled ? AppTheme.primary : AppTheme.textDim,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: _isEnabled ? AppTheme.primary : Colors.white10),
                ),
              ),
            ),
            
            if (_isEnabled)
             Padding(
               padding: const EdgeInsets.only(top: 16),
               child: Center(
                 child: Text(
                   'Status: Active', 
                   style: TextStyle(color: Colors.greenAccent.withAlpha(204), fontSize: 12)
                 ),
               ),
             )
          ],
        ),
      ),
    );
  }
}
