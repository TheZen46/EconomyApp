import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_notifier.dart';
import 'core/services/secure_storage_service.dart';
import 'core/services/hive_migration_service.dart';
import 'features/receipt_scanning/data/models/receipt_model.dart';
import 'features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'features/receipt_scanning/data/models/dashboard_config.dart';
import 'features/settings/data/models/taxonomy_model.dart';
import 'features/receipt_scanning/data/models/sync_item_model.dart';
import 'features/evault/data/models/asset_model.dart';
import 'features/evault/presentation/providers/asset_provider.dart';
import 'features/settings/presentation/providers/llm_provider.dart';
import 'features/boxes/data/models/box_model.dart';
import 'features/boxes/data/providers/boxes_provider.dart';
import 'features/invoices/data/models/invoice_model.dart';
import 'features/invoices/data/providers/invoices_provider.dart';
import 'features/auth/presentation/widgets/biometric_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 0. Global Error Boundary ───────────────────────────────────────────
  // Intercept uncaught Flutter framework errors (layout, rendering, etc.)
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('┌── FlutterError ──────────────────────────────────────');
    debugPrint('│ Exception: ${details.exceptionAsString()}');
    debugPrint('│ Library: ${details.library}');
    debugPrint('│ Context: ${details.context?.toStringDeep() ?? 'none'}');
    debugPrint('└─────────────────────────────────────────────────────');
    // In production, forward to a crash reporting service (e.g. Sentry/Firebase)
  };

  // Intercept uncaught async errors that escape the Dart event loop.
  // Returning true prevents the runtime from terminating the isolate.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('┌── Uncaught Async Error ──────────────────────────────');
    debugPrint('│ Error: $error');
    debugPrint('│ Stack: ${stack.toString().split('\n').take(5).join('\n│        ')}');
    debugPrint('└─────────────────────────────────────────────────────');
    // In production, forward to a crash reporting service (e.g. Sentry/Firebase)
    return true; // Handled — don't crash the isolate
  };

  // ── 1. Load environment variables from .env ────────────────────────────
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Warning: Could not load .env, attempting fallback: $e');
    try {
      await dotenv.load(fileName: '.env.example');
    } catch (_) {
      debugPrint('Notice: No environment asset bundle discovered.');
    }
  }

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? 'https://placeholder.supabase.co';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? 'placeholder-anon-key';

  // ── 2. Initialize Supabase with env-sourced credentials ────────────────
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  } catch (e) {
    debugPrint('Warning: Supabase initialization deferred/offline mode: $e');
  }

  // ── 3. Initialize Hive with AES encryption ─────────────────────────────
  await Hive.initFlutter();

  // Get or generate a 256-bit encryption key from the platform keychain
  final encryptionKey = await SecureStorageService.getHiveEncryptionKey();
  final cipher = HiveAesCipher(encryptionKey);

  // Register all Hive adapters
  Hive.registerAdapter(ReceiptModelAdapter());
  Hive.registerAdapter(ReceiptItemModelAdapter());
  Hive.registerAdapter(DashboardWidgetTypeAdapter());
  Hive.registerAdapter(DashboardItemAdapter());
  Hive.registerAdapter(TaxonomyItemModelAdapter());
  Hive.registerAdapter(TaxonomyConfigModelAdapter());
  Hive.registerAdapter(SyncItemModelAdapter());
  Hive.registerAdapter(AssetModelAdapter());
  Hive.registerAdapter(BoxModelAdapter());
  Hive.registerAdapter(InvoiceModelAdapter());

  // ── 4. Open Settings Box & Execute Structured Migrations ───────────────
  // HiveMigrationService.openBoxSafe() will:
  //   • Return the box on success.
  //   • On failure: back up the raw .hive file to getApplicationDocumentsDirectory()/hive_backups/,
  //     log to diagnostics, and throw SchemaCorruptionException — zero data wipe occurs.
  late final Box settingsBox;
  try {
    settingsBox = await HiveMigrationService.openBoxSafe('settings');
    // Execute structured schema migrations (e.g. schema_version = 2)
    await HiveMigrationService.runSchemaMigrations(settingsBox, cipher: cipher);
  } on SchemaCorruptionException catch (e) {
    debugPrint('FATAL Settings Box Corruption: $e');
    runApp(_DataRecoveryApp(exception: e));
    return;
  }

  // ── 5. Open Remaining Hive Boxes Safely with Encryption ─────────────────
  late final Box<ReceiptModel> receiptsBox;
  late final Box<SyncItemModel> syncBox;
  late final Box<AssetModel> assetsBox;
  late final Box<BoxModel> boxesBox;
  late final Box<InvoiceModel> invoicesBox;

  try {
    receiptsBox = await HiveMigrationService.openBoxSafe<ReceiptModel>(
      'receipts_v3',
      encryptionCipher: cipher,
    );
    syncBox = await HiveMigrationService.openBoxSafe<SyncItemModel>(
      'sync_queue',
      encryptionCipher: cipher,
    );
    assetsBox = await HiveMigrationService.openBoxSafe<AssetModel>(
      'assets',
      encryptionCipher: cipher,
    );
    boxesBox = await HiveMigrationService.openBoxSafe<BoxModel>(
      'boxes',
      encryptionCipher: cipher,
    );
    invoicesBox = await HiveMigrationService.openBoxSafe<InvoiceModel>(
      'invoices',
      encryptionCipher: cipher,
    );
  } on SchemaCorruptionException catch (e) {
    // A box failed to open. A backup was automatically created in hive_backups/.
    // Surface this to the user via the Data Recovery dialog — no data is lost.
    debugPrint('FATAL Database Box Corruption: $e');
    runApp(_DataRecoveryApp(exception: e));
    return;
  }

  // ── 6. Migrate plaintext secrets to secure storage ─────────────────────
  await _migrateSecretsToSecureStorage(settingsBox);

  // ── 6. Launch the app ──────────────────────────────────────────────────
  runApp(
    ProviderScope(
      overrides: [
        hiveBoxProvider.overrideWithValue(receiptsBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        syncBoxProvider.overrideWithValue(syncBox),
        assetsBoxProvider.overrideWithValue(assetsBox),
        boxesHiveBoxProvider.overrideWithValue(boxesBox),
        invoicesHiveBoxProvider.overrideWithValue(invoicesBox),
        themeProvider.overrideWith((ref) => ThemeNotifier(settingsBox)),
      ],
      child: const TAIdyApp(),
    ),
  );
}

/// One-time migration: moves any plaintext secrets from the Hive settings box
/// into flutter_secure_storage, then deletes them from Hive.
Future<void> _migrateSecretsToSecureStorage(Box settingsBox) async {
  const keysToMigrate = ['gemini_api_key', 'webhook_secret', 'webhook_url'];

  for (final key in keysToMigrate) {
    final plainValue = settingsBox.get(key);
    if (plainValue != null && plainValue is String && plainValue.isNotEmpty) {
      debugPrint('Migrating secret "$key" from Hive to secure storage...');
      await SecureStorageService.writeSecret(key, plainValue);
      await settingsBox.delete(key);
    }
  }

  // Clean up the old isLoggedIn flag (auth is now handled by Supabase sessions)
  if (settingsBox.containsKey('isLoggedIn')) {
    await settingsBox.delete('isLoggedIn');
  }
}

// ── Data Recovery App ───────────────────────────────────────────────────────

/// Minimal app shell shown when a [SchemaCorruptionException] is thrown during
/// startup. Informs the user that a backup was created and offers guidance,
/// rather than silently wiping data.
class _DataRecoveryApp extends StatelessWidget {
  final SchemaCorruptionException exception;
  const _DataRecoveryApp({required this.exception});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: _DataRecoveryScreen(exception: exception),
    );
  }
}

class _DataRecoveryScreen extends StatelessWidget {
  final SchemaCorruptionException exception;
  const _DataRecoveryScreen({required this.exception});

  @override
  Widget build(BuildContext context) {
    final hasBackup = exception.backupPath != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFD4183D), size: 48),
              const SizedBox(height: 24),
              const Text(
                'Data Recovery Required',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'tAIdy encountered a schema change in the local database '
                '(box: ${exception.boxName}) and could not open it safely.',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (hasBackup) ...[
                const Text(
                  '✓ Your data has been backed up automatically.',
                  style: TextStyle(
                      color: Color(0xFF4ADE80),
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    exception.backupPath!,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                ),
              ] else ...[
                const Text(
                  '⚠ A backup could not be created (no existing file found).',
                  style: TextStyle(color: Color(0xFFFBBF24), fontSize: 14),
                ),
              ],
              const SizedBox(height: 32),
              const Text(
                'To recover:\n'
                '  1. Copy the backup file to a safe location.\n'
                '  2. Restart the app — tAIdy will create a fresh database.\n'
                '  3. Contact support with your backup file for data restoration.',
                style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF002FA7),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    // Show technical details for support
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1A1A1A),
                        title: const Text('Technical Details',
                            style: TextStyle(color: Colors.white)),
                        content: SingleChildScrollView(
                          child: Text(
                            exception.toString(),
                            style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                                fontFamily: 'monospace'),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close',
                                style: TextStyle(color: Color(0xFF002FA7))),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('View Technical Details',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── App Shell ────────────────────────────────────────────────────────────────

class TAIdyApp extends ConsumerStatefulWidget {
  const TAIdyApp({super.key});

  @override
  ConsumerState<TAIdyApp> createState() => _TAIdyAppState();
}

class _TAIdyAppState extends ConsumerState<TAIdyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(modelUpdateServiceProvider.notifier).checkForUpdates();
      final llmService = ref.read(llmServiceProvider);
      await llmService.initialize();
      ref.read(isLlmLoadedProvider.notifier).state = llmService.isModelLoaded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);
    final isBalatro = ref.watch(isBalatroThemeProvider);

    return MaterialApp.router(
      title: 'tAIdy',
      theme: isBalatro ? AppTheme.balatroTheme : AppTheme.lightTheme,
      darkTheme: isBalatro ? AppTheme.balatroTheme : AppTheme.darkTheme,
      themeMode: isBalatro ? ThemeMode.dark : themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US')],
      builder: (context, child) => BiometricGuard(
        child: Stack(
          children: [
            UpgradeListenerWrapper(child: child),
            if (isBalatro)
              Positioned(
                top: 40,
                right: 16,
                child: Material(
                  color: Colors.transparent,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3333),
                      foregroundColor: Colors.white,
                      elevation: 8,
                      side: const BorderSide(color: Colors.white, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    onPressed: () => ref.read(isBalatroThemeProvider.notifier).disable(),
                    icon: const Icon(Icons.casino, size: 16, color: Colors.yellow),
                    label: const Text(
                      'CASH OUT ♠',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
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

class UpgradeListenerWrapper extends ConsumerWidget {
  final Widget? child;
  const UpgradeListenerWrapper({super.key, this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(modelUpdateServiceProvider, (previous, next) {
      if (next.message != null &&
          next.message!.isNotEmpty &&
          next.message != previous?.message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message!),
            backgroundColor: AppColors.accent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
    return child ?? const SizedBox();
  }
}
