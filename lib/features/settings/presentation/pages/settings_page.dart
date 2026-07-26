// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_notifier.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';

import '../../../../core/services/google_drive_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  int _devModeClicks = 0;
  bool _isDevMode = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    final box = ref.read(settingsBoxProvider);
    _isDevMode = box.get('is_dev_mode', defaultValue: false);
  }

  void _onVersionTap() {
    if (_isDevMode) return;
    setState(() {
      _devModeClicks++;
      if (_devModeClicks >= 7) {
        _isDevMode = true;
        ref.read(settingsBoxProvider).put('is_dev_mode', true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Developer Mode Unlocked! 🛠️')),
        );
      } else if (_devModeClicks > 2) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${7 - _devModeClicks} steps to developer...'), duration: const Duration(milliseconds: 500)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(modelUpdateServiceProvider);
    final updateNotifier = ref.read(modelUpdateServiceProvider.notifier);

    final storageUsageAsync = ref.watch(storageUsageProvider);
    final currentBudget = ref.watch(monthlyBudgetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section: General
          _buildSectionHeader('General'),
          _buildSettingsTile(
            context,
            icon: Icons.person_outline,
            title: 'Account',
            subtitle: 'Local User (Anonymous)',
            onTap: () {},
          ),
          _buildSettingsTile(
            context,
            icon: Icons.attach_money,
            title: 'Monthly Budget',
            subtitle: '\u20AC${currentBudget.toStringAsFixed(0)} Goal',
            onTap: () {
              final controller = TextEditingController(text: currentBudget.toStringAsFixed(0));
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppTheme.surface,
                  title: const Text('Set Monthly Budget', style: TextStyle(color: AppTheme.textMain)),
                  content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppTheme.textMain),
                    decoration: const InputDecoration(
                      prefixText: '\u20AC ',
                      hintText: '500',
                      hintStyle: TextStyle(color: AppTheme.textDim),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: AppTheme.textDim)),
                    ),
                    TextButton(
                      onPressed: () {
                        final val = double.tryParse(controller.text);
                        if (val != null) {
                          ref.read(monthlyBudgetProvider.notifier).setBudget(val);
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('Save', style: TextStyle(color: AppTheme.secondary)),
                    ),
                  ],
                ),
              );
            },
          ),
          Consumer(
            builder: (context, ref, child) {
              final themeMode = ref.watch(themeProvider);
              final isDark = themeMode == ThemeMode.dark;
              return _buildSettingsTile(
                context,
                icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                title: 'Appearance',
                subtitle: isDark ? 'Dark Mode' : 'Light Mode',
                onTap: () {
                  ref.read(themeProvider.notifier).toggle();
                },
              );
            },
          ),

          const SizedBox(height: 24),

          // Section: AI Engine
          _buildSectionHeader('AI Engine'),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.psychology, color: AppTheme.secondary),
                  title: const Text('Local AI Brain'),
                  subtitle: const Text(
                    'Manage on-device models',
                    style: TextStyle(color: AppTheme.textDim),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: AppTheme.textDim),
                  onTap: () {
                    context.push('/model_manager');
                  },
                ),
                Consumer(builder: (context, ref, child) {
                  final box = ref.watch(settingsBoxProvider);
                  final apiKey = box.get('gemini_api_key', defaultValue: '') as String;
                  final isEnabled = box.get('enable_gemini_ai', defaultValue: false) as bool;

                  return Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Enable Gemini AI 🧠'),
                        subtitle: Text(isEnabled ? 'Using Real AI Model' : 'Using Mock Data'),
                        activeThumbColor: AppTheme.secondary,
                        value: isEnabled,
                        onChanged: (val) {
                          box.put('enable_gemini_ai', val);
                          if (val && box.get('gemini_api_key') == null) {
                            box.put('gemini_api_key', '');
                          }
                          setState(() {});
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.key, color: AppTheme.secondary),
                        title: const Text('Gemini API Key'),
                        subtitle: Text(
                          apiKey.isNotEmpty ? 'Key Set (***********)' : 'Not Set',
                          style: const TextStyle(color: AppTheme.textDim),
                        ),
                        trailing: const Icon(Icons.edit, color: AppTheme.textDim, size: 18),
                        enabled: isEnabled,
                        onTap: () {
                          final controller = TextEditingController(text: apiKey);
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: AppTheme.surface,
                              title: const Text('Enter Gemini API Key', style: TextStyle(color: AppTheme.textMain)),
                              content: TextField(
                                controller: controller,
                                obscureText: true,
                                style: const TextStyle(color: AppTheme.textMain),
                                decoration: const InputDecoration(
                                  hintText: 'Paste Key Here',
                                  hintStyle: TextStyle(color: AppTheme.textDim),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textDim)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    box.put('gemini_api_key', controller.text.trim());
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Save', style: TextStyle(color: AppTheme.secondary)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  );
                }),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(color: Colors.white.withOpacity(0.05), height: 1),
                ),
                SwitchListTile(
                  value: false,
                  onChanged: (val) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cloud Inference coming in Phase 4+')),
                    );
                  },
                  title: const Text('Cloud Inference'),
                  subtitle: const Text('Offload to server for higher accuracy'),
                  activeThumbColor: AppTheme.secondary,
                  secondary: const Icon(Icons.cloud_outlined),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section: Categories
          _buildSectionHeader('Customization'),
          _buildSettingsTile(
            context,
            icon: Icons.label_outline,
            title: 'Categories',
            subtitle: 'Manage receipt tags',
            onTap: () {
              context.push('/taxonomy');
            },
          ),

          _buildSettingsTile(
            context,
            icon: Icons.hub_outlined,
            title: 'Integrations & Webhooks',
            subtitle: 'The Connector',
            onTap: () {
              context.push('/integrations');
            },
          ),

          const SizedBox(height: 24),

          // Section: Data & Privacy
          _buildSectionHeader('Data & Privacy'),
          _buildSettingsTile(
            context,
            icon: Icons.delete_outline,
            title: 'Clear Data',
            subtitle: 'Manage local and cloud cleanup',
            isDestructive: true,
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppTheme.surface,
                  title: const Text('Clear Data', style: TextStyle(color: AppTheme.textMain)),
                  content: const Text(
                    'Choose how you want to clear your data. This action cannot be undone.',
                    style: TextStyle(color: AppTheme.textDim),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: AppTheme.textDim)),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(receiptListProvider.notifier).clearAll(includeCloud: false);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Local data cleared')),
                        );
                      },
                      child: const Text('Device Only', style: TextStyle(color: AppTheme.error)),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(receiptListProvider.notifier).clearAll(includeCloud: true);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All data wiped (Cloud + Local)')),
                        );
                      },
                      child: const Text(
                        'Everywhere',
                        style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          storageUsageAsync.when(
            data: (bytes) => _buildSettingsTile(
              context,
              icon: Icons.cloud_done,
              title: 'Gold Dataset Contribution',
              subtitle: 'Size: ${(bytes / 1024).toStringAsFixed(1)} KB (Calculated from storage)',
              onTap: () => ref.refresh(storageUsageProvider),
            ),
            loading: () => _buildSettingsTile(
              context,
              icon: Icons.cloud_sync,
              title: 'Gold Dataset Contribution',
              subtitle: 'Calculating...',
              onTap: () {},
            ),
            error: (err, _) => _buildSettingsTile(
              context,
              icon: Icons.error_outline,
              title: 'Gold Dataset Contribution',
              subtitle: 'Error fetching stats',
              onTap: () => ref.refresh(storageUsageProvider),
              isDestructive: true,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final settingsBox = ref.read(settingsBoxProvider);
                settingsBox.put('isLoggedIn', false);
                context.go('/');
              },
              icon: const Icon(Icons.logout, color: AppTheme.error),
              label: const Text('Log Out', style: TextStyle(color: AppTheme.error)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.error),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          if (_isDevMode) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('Admin Tools'),

            Consumer(builder: (context, ref, child) {
              final box = ref.watch(settingsBoxProvider);
              final useDrive = box.get('use_google_drive_storage', defaultValue: false);
              return SwitchListTile(
                title: const Text('Storage Provider: Google Drive'),
                subtitle: Text(useDrive ? 'Uploading to Drive (tAIdy_Data)' : 'Uploading to Supabase (Default)'),
                activeThumbColor: AppTheme.secondary,
                secondary: Icon(useDrive ? Icons.add_to_drive : Icons.cloud_upload_outlined, color: AppTheme.textDim),
                value: useDrive,
                onChanged: (val) {
                  box.put('use_google_drive_storage', val);
                  setState(() {});
                },
              );
            }),

            _buildSettingsTile(
              context,
              icon: Icons.backup,
              title: 'Archive All Data Now',
              subtitle: _isUploading ? 'Uploading...' : 'Tap to backup Hive boxes',
              onTap: _isUploading ? () {} : () async {
                setState(() => _isUploading = true);
                try {
                  await googleDriveService.archiveAllData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Backup successful! (Clean Scaffold)')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${googleDriveService.lastError ?? e}')),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isUploading = false);
                }
              },
            ),
          ],

          const SizedBox(height: 48),
          Center(
            child: GestureDetector(
              onTap: _onVersionTap,
              child: Text(
                'tAIdy v0.3.0 (Beta)${_isDevMode ? " [DEV]" : ""}',
                style: TextStyle(color: AppTheme.textDim.withOpacity(0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isDestructive ? AppTheme.error : AppTheme.textDim,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isDestructive ? AppTheme.error : AppTheme.textMain,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(color: AppTheme.textDim))
            : null,
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textDim, size: 18),
        onTap: onTap,
      ),
    );
  }
}
