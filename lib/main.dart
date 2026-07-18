import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/receipt_scanning/data/models/receipt_model.dart';
import 'features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'features/receipt_scanning/data/models/dashboard_config.dart';
import 'features/settings/data/models/taxonomy_model.dart';
import 'features/receipt_scanning/data/models/sync_item_model.dart';
import 'features/evault/data/models/asset_model.dart';
import 'features/evault/presentation/providers/asset_provider.dart';
import 'features/settings/presentation/providers/llm_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // TODO: Replace with actual credentials provided by USER
  await Supabase.initialize(
    url: 'https://dodxwqwvfaicmaiedsgj.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRvZHh3cXd2ZmFpY21haWVkc2dqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk0MTkwNzcsImV4cCI6MjA4NDk5NTA3N30.PTKWP5TNaEjNI4YzliJAUOhHa0Vsif-57Qy9agcM-5A',
  );

  await Hive.initFlutter();
  Hive.registerAdapter(ReceiptModelAdapter());
  Hive.registerAdapter(ReceiptItemModelAdapter());
  Hive.registerAdapter(DashboardWidgetTypeAdapter());
  Hive.registerAdapter(DashboardItemAdapter());
  Hive.registerAdapter(TaxonomyItemModelAdapter());
  Hive.registerAdapter(TaxonomyConfigModelAdapter());
  Hive.registerAdapter(SyncItemModelAdapter());
  Hive.registerAdapter(AssetModelAdapter());
  
  // Open the boxes with Schema Error Recovery
  Box<ReceiptModel> receiptsBox;
  try {
    receiptsBox = await Hive.openBox<ReceiptModel>('receipts_v3');
  } catch (e) {
    debugPrint('Hive Schema Error: $e. Wiping box...');
    // Try to delete v2 if it somehow gets corrupted too, but strictly cleaner
    await Hive.deleteBoxFromDisk('receipts_v3');
    receiptsBox = await Hive.openBox<ReceiptModel>('receipts_v3');
  }

  final settingsBox = await Hive.openBox('settings');
  final syncBox = await Hive.openBox<SyncItemModel>('sync_queue');
  final assetsBox = await Hive.openBox<AssetModel>('assets');

  runApp(
    ProviderScope(
      overrides: [
        hiveBoxProvider.overrideWithValue(receiptsBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        syncBoxProvider.overrideWithValue(syncBox),
        assetsBoxProvider.overrideWithValue(assetsBox),
      ],
      child: const TAIdyApp(),
    ),
  );
}

class TAIdyApp extends ConsumerStatefulWidget {
  const TAIdyApp({super.key});

  @override
  ConsumerState<TAIdyApp> createState() => _TAIdyAppState();
}

class _TAIdyAppState extends ConsumerState<TAIdyApp> {
  @override
  void initState() {
    super.initState();
    // Trigger OTA check after build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(modelUpdateServiceProvider.notifier).checkForUpdates();
      // Initialize Local Brain if installed
      final llmService = ref.read(llmServiceProvider);
      await llmService.initialize();
      ref.read(isLlmLoadedProvider.notifier).state = llmService.isModelLoaded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    
    // Listen to update state for global feedback
    // Listener moved to UpgradeListenerWrapper to ensure ScaffoldMessenger context is available.

    return MaterialApp.router(
      title: 'tAIdy',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // Wrap builder to ensure ScaffoldMessenger is available if needed above MaterialApp context? 
      // Actually listen needs to be inside a child of MaterialApp for ScaffoldMessenger to work via context?
      // No, we are inside TAIdyApp which is above MaterialApp. 
      // To use ScaffoldMessenger.of(context), we need a context below MaterialApp.
      // Refactoring to use a "RootScaffold" or similar wrapper inside router is better.
      // For now, let's inject a global key or just move the listener to HomePage.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'), // English, no country code
      ],
      builder: (context, child) => UpgradeListenerWrapper(child: child),
    );
  }
}

class UpgradeListenerWrapper extends ConsumerWidget {
  final Widget? child;
  const UpgradeListenerWrapper({super.key, this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(modelUpdateServiceProvider, (previous, next) {
      // Only show snackbar if the message CHANGED and is not empty
      if (next.message != null && 
          next.message!.isNotEmpty && 
          next.message != previous?.message) {
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message!),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
    return child ?? const SizedBox();
  }
}
