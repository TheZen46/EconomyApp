import 'dart:async';

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
import 'core/services/secure_session_storage.dart';
import 'core/services/hive_migration_service.dart';
import 'core/providers/storage_providers.dart';
import 'core/recovery/data_recovery_app.dart';
import 'features/receipt_scanning/data/models/receipt_model.dart';
import 'features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'features/receipt_scanning/data/models/dashboard_config.dart';
import 'features/settings/data/models/taxonomy_model.dart';
import 'features/receipt_scanning/data/models/sync_item_model.dart';
import 'features/evault/data/models/asset_model.dart';
import 'features/settings/presentation/providers/llm_provider.dart';
import 'features/settings/presentation/providers/taxonomy_provider.dart';
import 'features/boxes/data/models/box_model.dart';
import 'features/invoices/data/models/invoice_model.dart';
import 'features/auth/presentation/widgets/biometric_guard.dart';
import 'core/services/telemetry_service.dart';
import 'core/providers/supabase_providers.dart';
import 'core/sync/models/sync_outbox_item.dart';
import 'core/sync/sync_providers.dart';
import 'features/settings/data/models/user_profile_model.dart';

/// Application entrypoint initializing telemetry, secure storage, AES-encrypted Hive boxes,
/// and Riverpod provider overrides before launching [TAIdyApp].
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // ── 0. Global Telemetry & Error Boundary ────────────────────────────────
  await TelemetryService.instance.initialize();
  TelemetryService.instance.setupGlobalErrorHandlers();

  // ── 1. Load environment variables (Compile-time defines & local dotenv) ──
  const defineSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const defineSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Expected in release builds where .env is omitted from asset manifests for security.
  }

  final supabaseUrl = defineSupabaseUrl.isNotEmpty
      ? defineSupabaseUrl
      : (dotenv.isInitialized ? (dotenv.maybeGet('SUPABASE_URL') ?? '') : '');
  final supabaseAnonKey = defineSupabaseAnonKey.isNotEmpty
      ? defineSupabaseAnonKey
      : (dotenv.isInitialized ? (dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '') : '');

  // ── 2. Initialize Supabase with env-sourced credentials ────────────────
  // Without an initialized client, supabaseClientProvider is null and the app
  // runs local-only. Placeholders and invalid formats are treated as unconfigured.
  if (isValidSupabaseUrl(supabaseUrl) && isValidSupabaseAnonKey(supabaseAnonKey)) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        authOptions: FlutterAuthClientOptions(
          // Tokens go to the keychain/keystore, not plaintext preferences.
          localStorage: SecureSessionStorage(
            legacyPreferencesKey: 'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Warning: Supabase initialization failed, running local-only: $e');
    }
  } else {
    debugPrint('Notice: Supabase credentials unconfigured or template placeholders; running in offline/local-only mode.');
  }

  // ── 3. Initialize Hive with AES encryption ─────────────────────────────
  await Hive.initFlutter();

  // Get or generate a 256-bit encryption key from the platform keychain.
  // A missing key with existing encrypted files means the data can no longer be
  // decrypted; say so instead of silently generating a new key.
  final HiveAesCipher cipher;
  final secureStorage = SecureStorageService();
  try {
    if (!await secureStorage.hasHiveEncryptionKey() &&
        await HiveMigrationService.boxFilesExist(_encryptedBoxNames)) {
      debugPrint('FATAL Hive encryption key missing for existing encrypted boxes');
      runApp(DataRecoveryApp(recovery: StartupRecovery.encryptionKeyLost(_encryptedBoxNames)));
      return;
    }
    cipher = HiveAesCipher(await secureStorage.getHiveEncryptionKey());
  } catch (e) {
    debugPrint('FATAL Secure storage unavailable: $e');
    runApp(DataRecoveryApp(recovery: StartupRecovery.secureStorageUnavailable(e)));
    return;
  }

  // Register all Hive adapters.
  // Authoritative typeId assignments and restrictions are documented in `docs/contracts/hive_registry.md`.
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
  Hive.registerAdapter(SyncOutboxItemAdapter());
  Hive.registerAdapter(UserProfileModelAdapter());

  // ── 4. Open Settings Box & Execute Structured Migrations ───────────────
  // HiveMigrationService.openBoxSafe() will:
  //   • Return the box on success.
  //   • On failure: back up the raw .hive file to getApplicationDocumentsDirectory()/hive_backups/,
  //     log to diagnostics, and throw SchemaCorruptionException — zero data wipe occurs.
  late final Box settingsBox;
  try {
    settingsBox = await HiveMigrationService.openBoxSafe(
      'settings',
      encryptionCipher: cipher,
      migrateFromPlaintext: true,
    );
    // Execute structured schema migrations (e.g. schema_version = 2)
    await HiveMigrationService.runSchemaMigrations(settingsBox, cipher: cipher);
  } on SchemaCorruptionException catch (e) {
    debugPrint('FATAL Settings Box Corruption: $e');
    runApp(DataRecoveryApp(recovery: StartupRecovery.unreadableBox(e)));
    return;
  }

  // ── 5. Open Remaining Hive Boxes Safely with Encryption ─────────────────
  late final Box<ReceiptModel> receiptsBox;
  late final Box<SyncItemModel> syncBox;
  late final Box<AssetModel> assetsBox;
  late final Box<BoxModel> boxesBox;
  late final Box<InvoiceModel> invoicesBox;
  late final Box<SyncOutboxItem> outboxBox;
  late final Box<TaxonomyConfigModel> taxonomyBox;

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
    outboxBox = await HiveMigrationService.openBoxSafe<SyncOutboxItem>(
      'sync_outbox',
      encryptionCipher: cipher,
    );
    taxonomyBox = await HiveMigrationService.openBoxSafe<TaxonomyConfigModel>(
      'taxonomy_config',
      encryptionCipher: cipher,
      migrateFromPlaintext: true,
    );
  } on SchemaCorruptionException catch (e) {
    // A box failed to open. A backup was automatically created in hive_backups/.
    // Surface this to the user via the Data Recovery dialog — no data is lost.
    debugPrint('FATAL Database Box Corruption: $e');
    runApp(DataRecoveryApp(recovery: StartupRecovery.unreadableBox(e)));
    return;
  }

  // ── 6. Migrate plaintext secrets to secure storage ─────────────────────
  await _migrateSecretsToSecureStorage(settingsBox, secureStorage);

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
        outboxHiveBoxProvider.overrideWithValue(outboxBox),
        taxonomyBoxProvider.overrideWithValue(taxonomyBox),
        themeProvider.overrideWith((ref) => ThemeNotifier(settingsBox)),
      ],
      child: const TAIdyApp(),
    ),
  );
  } catch (error, stack) {
    debugPrint('FATAL Unhandled initialization error during startup: $error\n$stack');
    try {
      await TelemetryService.instance.recordCrash(
        error: error,
        stackTrace: stack,
        errorType: 'Startup.FatalInitialization',
      );
    } catch (_) {}
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 56, color: Color(0xFFEF4444)),
                    const SizedBox(height: 16),
                    const Text(
                      'Initialization Failed',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Moves any plaintext secrets left in the Hive settings box (written by
/// earlier versions) into flutter_secure_storage, then deletes them from Hive.
/// Secure storage is the only location these keys are read from, so the
/// routine is a no-op once nothing is left to move.
Future<void> _migrateSecretsToSecureStorage(Box settingsBox, SecureStorageService secureStorage) async {
  const keysToMigrate = ['gemini_api_key', 'webhook_secret', 'webhook_url'];

  for (final key in keysToMigrate) {
    final plainValue = settingsBox.get(key);
    if (plainValue != null && plainValue is String && plainValue.isNotEmpty) {
      debugPrint('Migrating secret "$key" from Hive to secure storage...');
      await secureStorage.writeSecret(key, plainValue);
      await settingsBox.delete(key);
    }
  }

  // Clean up the old isLoggedIn flag (auth is now handled by Supabase sessions)
  if (settingsBox.containsKey('isLoggedIn')) {
    await settingsBox.delete('isLoggedIn');
  }
}

// ── Startup Recovery ──────────────────────────────────────────────────────────

/// Boxes opened with the Hive encryption key (see steps 4 and 5 of [main]).
const List<String> _encryptedBoxNames = [
  'settings',
  'taxonomy_config',
  'receipts_v3',
  'sync_queue',
  'assets',
  'boxes',
  'invoices',
  'sync_outbox',
];

/// Root widget configuring the application theme, router, localizations, and biometric guards.
class TAIdyApp extends ConsumerStatefulWidget {
  /// Creates the root [TAIdyApp] instance.
  const TAIdyApp({super.key});

  @override
  ConsumerState<TAIdyApp> createState() => _TAIdyAppState();
}

class _TAIdyAppState extends ConsumerState<TAIdyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Each step runs on its own, so that a failure in one does not skip the
      // others (in particular the creation of the SyncManager).
      await _startupTask('model update check', () async {
        await ref.read(modelUpdateServiceProvider.notifier).checkForUpdates();
      });
      await _startupTask('LLM initialization', () async {
        final llmService = ref.read(llmServiceProvider);
        await llmService.initialize();
        if (mounted) ref.read(isLlmLoadedProvider.notifier).state = llmService.isModelLoaded;
      });
      await _startupTask('VLM readiness initialization', () async {
        final vlmService = ref.read(vlmEngineServiceProvider);
        final vlmSuccess = await vlmService.initialize();
        if (mounted) {
          ref.read(isVlmReadyProvider.notifier).state = vlmSuccess;
          if (vlmSuccess) {
            ref.read(isLlmLoadedProvider.notifier).state = true;
          }
        }
      });
      await _startupTask('SyncManager creation', () async {
        if (mounted) ref.read(syncManagerProvider);
      });
    });
  }

  Future<void> _startupTask(String name, Future<void> Function() task) async {
    try {
      await task();
    } catch (e, stack) {
      debugPrint('Startup task "$name" failed: $e');
      unawaited(TelemetryService.instance.recordCrash(
        error: e,
        stackTrace: stack,
        errorType: 'Startup.$name',
      ));
    }
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

/// Listens for over-the-air model update notifications and displays floating SnackBars.
class UpgradeListenerWrapper extends ConsumerWidget {
  /// The child widget subtree to wrap.
  final Widget? child;

  /// Creates an [UpgradeListenerWrapper].
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
