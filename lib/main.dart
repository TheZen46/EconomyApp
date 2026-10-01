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
import 'core/recovery/data_recovery_app.dart';
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
import 'core/services/telemetry_service.dart';
import 'core/providers/supabase_providers.dart';
import 'core/sync/models/sync_outbox_item.dart';
import 'core/sync/sync_providers.dart';
import 'features/settings/data/models/user_profile_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 0. Global Telemetry & Error Boundary ────────────────────────────────
  await TelemetryService.instance.initialize();
  TelemetryService.instance.setupGlobalErrorHandlers();

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
  // Without an initialized client, supabaseClientProvider is null and the app
  // runs local-only.
  if (isValidSupabaseUrl(supabaseUrl)) {
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
    debugPrint('Warning: SUPABASE_URL is not a valid http(s) URL, running local-only.');
  }

  // ── 3. Initialize Hive with AES encryption ─────────────────────────────
  await Hive.initFlutter();

  // Get or generate a 256-bit encryption key from the platform keychain.
  // A missing key with existing encrypted files means the data can no longer be
  // decrypted; say so instead of silently generating a new key.
  final HiveAesCipher cipher;
  try {
    if (!await SecureStorageService.hasHiveEncryptionKey() &&
        await HiveMigrationService.boxFilesExist(_encryptedBoxNames)) {
      debugPrint('FATAL Hive encryption key missing for existing encrypted boxes');
      runApp(DataRecoveryApp(recovery: StartupRecovery.encryptionKeyLost(_encryptedBoxNames)));
      return;
    }
    cipher = HiveAesCipher(await SecureStorageService.getHiveEncryptionKey());
  } catch (e) {
    debugPrint('FATAL Secure storage unavailable: $e');
    runApp(DataRecoveryApp(recovery: StartupRecovery.secureStorageUnavailable(e)));
    return;
  }

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
  Hive.registerAdapter(SyncOutboxItemAdapter());
  Hive.registerAdapter(UserProfileModelAdapter());

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
  } on SchemaCorruptionException catch (e) {
    // A box failed to open. A backup was automatically created in hive_backups/.
    // Surface this to the user via the Data Recovery dialog — no data is lost.
    debugPrint('FATAL Database Box Corruption: $e');
    runApp(DataRecoveryApp(recovery: StartupRecovery.unreadableBox(e)));
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
        outboxHiveBoxProvider.overrideWithValue(outboxBox),
        themeProvider.overrideWith((ref) => ThemeNotifier(settingsBox)),
      ],
      child: const TAIdyApp(),
    ),
  );
}

/// Moves any plaintext secrets left in the Hive settings box (written by
/// earlier versions) into flutter_secure_storage, then deletes them from Hive.
/// Secure storage is the only location these keys are read from, so the
/// routine is a no-op once nothing is left to move.
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

// ── Startup Recovery ──────────────────────────────────────────────────────────

/// Boxes opened with the Hive encryption key (see step 5 of [main]).
const List<String> _encryptedBoxNames = [
  'receipts_v3',
  'sync_queue',
  'assets',
  'boxes',
  'invoices',
  'sync_outbox',
];

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
