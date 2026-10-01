import 'package:flutter/material.dart';

import '../services/hive_migration_service.dart';

/// Why startup could not open local storage, and what the user can do about it.
class StartupRecovery {
  final String title;
  final String explanation;

  /// Boxes whose files the user may move aside to start with empty ones. Empty
  /// when starting over would not help (for example when secure storage itself
  /// is unavailable).
  final List<String> resettableBoxes;

  /// Automated copy of the failed box, if one was created.
  final String? backupPath;

  /// Technical description for support.
  final String details;

  const StartupRecovery({
    required this.title,
    required this.explanation,
    required this.resettableBoxes,
    required this.details,
    this.backupPath,
  });

  /// A box could not be opened (corrupt file, wrong key or unreadable records).
  factory StartupRecovery.unreadableBox(SchemaCorruptionException e) {
    return StartupRecovery(
      title: 'Data Recovery Required',
      explanation: 'tAIdy could not open its local database "${e.boxName}". '
          'The file is kept unchanged; tAIdy will not overwrite it on its own.',
      resettableBoxes: [e.boxName],
      backupPath: e.backupPath,
      details: e.toString(),
    );
  }

  /// Encrypted box files exist, but the key that encrypted them is missing.
  factory StartupRecovery.encryptionKeyLost(List<String> boxNames) {
    return StartupRecovery(
      title: 'Encryption Key Not Found',
      explanation: 'Your local data is encrypted with a key kept in the secure storage '
          'of this device, and that key is missing (for example after restoring the app '
          'to a new device or clearing its credentials). The encrypted data cannot be read '
          'without it. Data synchronized to your account can be restored after you start '
          'over, using Replicate Cloud Data.',
      resettableBoxes: boxNames,
      details: 'Missing secure storage key for encrypted boxes: ${boxNames.join(', ')}',
    );
  }

  /// The platform secure storage could not be read.
  factory StartupRecovery.secureStorageUnavailable(Object error) {
    return StartupRecovery(
      title: 'Secure Storage Unavailable',
      explanation: 'tAIdy could not read its encryption key from the secure storage of '
          'this device, so your data was not opened. Unlock the device or its keychain '
          'and open tAIdy again. On Linux, a Secret Service provider (for example GNOME '
          'Keyring) must be running.',
      resettableBoxes: const [],
      details: error.toString(),
    );
  }
}

/// Minimal app shown instead of the main app when local storage cannot be
/// opened at startup. It never deletes data on its own: starting over moves the
/// affected files into the backup folder, and only on explicit request.
class DataRecoveryApp extends StatelessWidget {
  final StartupRecovery recovery;
  final Future<String?> Function(List<String> boxNames) quarantine;

  const DataRecoveryApp({
    super.key,
    required this.recovery,
    this.quarantine = HiveMigrationService.quarantineBoxes,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: DataRecoveryScreen(recovery: recovery, quarantine: quarantine),
    );
  }
}

class DataRecoveryScreen extends StatefulWidget {
  final StartupRecovery recovery;
  final Future<String?> Function(List<String> boxNames) quarantine;

  const DataRecoveryScreen({super.key, required this.recovery, required this.quarantine});

  @override
  State<DataRecoveryScreen> createState() => _DataRecoveryScreenState();
}

class _DataRecoveryScreenState extends State<DataRecoveryScreen> {
  bool _working = false;
  bool _reset = false;
  String? _quarantinePath;
  String? _error;

  Future<void> _confirmAndReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Start with an empty database?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'The affected files are moved to the backup folder, not deleted. tAIdy then '
          'starts without the data they contain.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start over')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final path = await widget.quarantine(widget.recovery.resettableBoxes);
      setState(() {
        _reset = true;
        _quarantinePath = path;
      });
    } catch (e) {
      setState(() => _error = 'The files could not be moved: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = widget.recovery;
    const body = TextStyle(color: Colors.white70, fontSize: 14, height: 1.5);
    const mono = TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace');

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD4183D), size: 48),
              const SizedBox(height: 24),
              Text(
                recovery.title,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(recovery.explanation, style: body),
              if (recovery.backupPath != null) ...[
                const SizedBox(height: 16),
                const Text('A copy of the file was saved to:', style: body),
                const SizedBox(height: 4),
                SelectableText(recovery.backupPath!, style: mono),
              ],
              const SizedBox(height: 32),
              if (_reset) ...[
                const Text(
                  'Done. Close tAIdy completely and open it again to continue.',
                  style: TextStyle(color: Color(0xFF4ADE80), fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (_quarantinePath != null) ...[
                  const SizedBox(height: 8),
                  const Text('The previous files are in:', style: body),
                  const SizedBox(height: 4),
                  SelectableText(_quarantinePath!, style: mono),
                ],
              ] else if (recovery.resettableBoxes.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4183D),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _working ? null : _confirmAndReset,
                    child: const Text('Start with an empty database', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 13)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1A1A),
                      title: const Text('Technical Details', style: TextStyle(color: Colors.white)),
                      content: SingleChildScrollView(child: SelectableText(recovery.details, style: mono)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                      ],
                    ),
                  ),
                  child: const Text('View Technical Details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
