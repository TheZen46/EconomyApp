// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_notifier.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO: Replace with actual credentials provided by USER
  await Supabase.initialize(
    url: 'https://dodxwqwvfaicmaiedsgj.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRvZHh3cXd2ZmFpY21haWVkc2dqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk0MTkwNzcsImV4cCI6MjA4NDk5NTA3N30.PTKWP5TNaEjNI4YzliJAUOhHa0Vsif-57Qy9agcM-5A',
  );

  await Hive.initFlutter();

  // Existing adapters
  Hive.registerAdapter(ReceiptModelAdapter());
  Hive.registerAdapter(ReceiptItemModelAdapter());
  Hive.registerAdapter(DashboardWidgetTypeAdapter());
  Hive.registerAdapter(DashboardItemAdapter());
  Hive.registerAdapter(TaxonomyItemModelAdapter());
  Hive.registerAdapter(TaxonomyConfigModelAdapter());
  Hive.registerAdapter(SyncItemModelAdapter());
  Hive.registerAdapter(AssetModelAdapter());

  // New adapters
  Hive.registerAdapter(BoxModelAdapter());
  Hive.registerAdapter(InvoiceModelAdapter());

  // Open existing boxes
  late final receiptsBox;
  try {
    receiptsBox = await Hive.openBox<ReceiptModel>('receipts_v3');
  } catch (e) {
    debugPrint('Hive Schema Error: $e. Wiping box...');
    await Hive.deleteBoxFromDisk('receipts_v3');
    receiptsBox = await Hive.openBox<ReceiptModel>('receipts_v3');
  }

  final settingsBox = await Hive.openBox('settings');
  final syncBox = await Hive.openBox<SyncItemModel>('sync_queue');
  final assetsBox = await Hive.openBox<AssetModel>('assets');

  // Open new boxes
  final boxesBox = await Hive.openBox<BoxModel>('boxes');
  final invoicesBox = await Hive.openBox<InvoiceModel>('invoices');

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
      ref.read(modelUpdateServiceProvider.notifier).checkForUpdates();
      final llmService = ref.read(llmServiceProvider);
      await llmService.initialize();
      ref.read(isLlmLoadedProvider.notifier).state = llmService.isModelLoaded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'tAIdy',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US')],
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
