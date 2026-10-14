# tAIdy Architecture

This document describes the system topology, component boundaries, state management, persistence
model and invariants of the tAIdy (EconomyApp) Flutter client and its Supabase backend, as implemented
at revision `c66e079`. It states the intent behind each design decision and, where the implementation
does not yet satisfy an intended invariant, references the corresponding finding in
`audit/findings_report.md` (identifiers of the form `TAIDY-XNN`) and its tracking issue.

Companion documents:

- `docs/data_flow.md`: request and data life cycles, step by step.
- `docs/troubleshooting.md`: failure modes, configuration errors and triage procedures.

## Contents

1. [System Topology](#1-system-topology)
2. [Module Layout and Layer Boundaries](#2-module-layout-and-layer-boundaries)
3. [Bootstrap Sequence](#3-bootstrap-sequence)
4. [State Management and Dependency Injection](#4-state-management-and-dependency-injection)
5. [Local Persistence](#5-local-persistence)
6. [Authentication, Routing and Access Control](#6-authentication-routing-and-access-control)
7. [Receipt Extraction Subsystem](#7-receipt-extraction-subsystem)
8. [Synchronization Subsystem](#8-synchronization-subsystem)
9. [Remote Backend Contract](#9-remote-backend-contract)
10. [Financial Core](#10-financial-core)
11. [Cross-Cutting Concerns](#11-cross-cutting-concerns)
12. [System Invariants](#12-system-invariants)
13. [Architectural Decision Records](#13-architectural-decision-records)

---

## 1. System Topology

tAIdy is a single Flutter code base targeting Android, iOS, web, Windows, macOS and Linux. The client
owns the authoritative working copy of user data in local encrypted storage and treats the cloud as a
replica. Four external systems are contacted: Supabase (authentication, PostgreSQL through PostgREST,
object storage), Google Gemini (optional cloud extraction), Hugging Face (model downloads) and
user-configured endpoints (webhooks, Google Drive).

```
+----------------------------------------------------------------------------------+
|                               Flutter client process                              |
|                                                                                   |
|  +-------------------+    +----------------------+    +------------------------+  |
|  | Presentation      |    | Riverpod providers   |    | Data / services        |  |
|  | pages, widgets    +--->+ StateNotifiers,      +--->+ repositories,          |  |
|  | GoRouter          |    | service providers    |    | data sources, sync     |  |
|  +-------------------+    +----------------------+    +-----+-----------+------+  |
|                                                             |           |         |
|        +----------------------------------------------------+           |         |
|        |                     |                     |                    |         |
|        v                     v                     v                    v         |
|  +------------+      +---------------+     +---------------+    +--------------+  |
|  | Hive boxes |      | Secure storage|     | SQLite        |    | VLM worker   |  |
|  | (AES-256)  |      | (OS keychain) |     | episodic mem. |    | isolate      |  |
|  +------------+      +---------------+     +---------------+    +------+-------+  |
|                                                                        | dart:ffi |
|                                                                 +------v-------+  |
|                                                                 | libreceipt_  |  |
|                                                                 | engine (C++) |  |
|                                                                 +--------------+  |
+------------+------------------+-------------------+-------------------+-----------+
             |                  |                   |                   |
             v                  v                   v                   v
     +---------------+  +----------------+  +----------------+  +------------------+
     | Supabase      |  | Google Gemini  |  | Hugging Face   |  | Webhook endpoint |
     | Auth, REST,   |  | (optional)     |  | model files    |  | Google Drive     |
     | Storage       |  |                |  |                |  | (optional)       |
     +---------------+  +----------------+  +----------------+  +------------------+
```

The topology follows an offline-first model: every user-visible mutation is first committed to a
local Hive box, and network activity is deferred to background synchronization. The rationale is
that receipts are captured in shops, often with poor connectivity, and that the application must
remain usable without an account. The consequence is that correctness depends on the replication
protocol (Section 8), which is where most defects recorded in the audit are located.

## 2. Module Layout and Layer Boundaries

### 2.1 Directory layout

| Path | Responsibility |
|---|---|
| `lib/main.dart` | Process entry point, bootstrap pipeline, root `MaterialApp.router`, data-recovery shell. |
| `lib/core/constants` | Application constants and the default category taxonomy. |
| `lib/core/crdt` | Hybrid logical clock, LWW register, vector clock, receipt CRDT and `CrdtSyncEngine`. Not referenced by application code (`TAIDY-A06`). |
| `lib/core/error` | `Failure` hierarchy used in `Either<Failure, T>` results. |
| `lib/core/financial` | Fixed-point `Money`, `CurrencyRatio`, `TaxEngine`. Reachable only from `TaxComplianceService`. |
| `lib/core/privacy` | `PiiScrubberService` (regular-expression redaction). |
| `lib/core/routes` | `routerProvider` (GoRouter) and route constants (`AppRoutes`). |
| `lib/core/services` | Cross-feature services: secure storage, Hive migration, telemetry, biometrics, export, Google Drive, AI service contract, legacy LLM, VLM engine. |
| `lib/core/sync` | Outbox model and service, `SyncManager`, sync providers. |
| `lib/core/theme`, `lib/core/utils` | Theme notifiers, JSON repair utilities, error mapping. |
| `lib/features/auth` | Supabase authentication repository, `AuthNotifier`, `RouterNotifier`, `BiometricGuard`. |
| `lib/features/boxes` | Spending contexts ("boxes") and the burn-rate calculator. |
| `lib/features/evault` | Warranty-tracked assets. |
| `lib/features/invoices` | Issued invoices and numbering. |
| `lib/features/receipt_scanning` | Capture, extraction, review, receipt repository, legacy upload queue, dashboard. |
| `lib/features/settings` | Settings pages, model manager, taxonomy editor, webhook service, AI readiness flags. |
| `lib/features/sync` | Post-login replication engine (`SyncEngine`) and progress UI. |
| `native/` | C++ inference engine, image preprocessing, HNSW index, GBNF grammars. |
| `supabase/` | Schema, migrations and seed scripts. |

### 2.2 Layer responsibilities

Each feature follows a presentation / domain / data split:

- **Presentation** (`presentation/pages`, `presentation/widgets`, `presentation/providers`) renders
  state and dispatches intents to `StateNotifier` instances.
- **Domain** (`domain/entities`, `domain/repositories`) defines immutable entities (for example the
  freezed `Receipt` and `ReceiptItem`) and repository interfaces returning `Either<Failure, T>`.
- **Data** (`data/models`, `data/datasources`, `data/repositories`) implements persistence and network
  access. Hive models (`ReceiptModel`, `BoxModel`, `InvoiceModel`, `AssetModel`) double as JSON
  serializers for Supabase rows.

The split was chosen so that business rules can be tested without Flutter bindings and so that the
storage engine can be replaced behind repository interfaces. In practice only the receipt and
authentication features implement repository interfaces; boxes, invoices and assets are accessed by
their notifiers directly through Hive boxes.

### 2.3 Dependency direction

The intended dependency direction is `presentation -> domain <- data`, with `core` depended upon by
features and never the reverse. The implementation contains reverse edges: `lib/core/sync` imports
feature models and providers, and `lib/core/services/biometric_service.dart` and
`lib/core/theme/theme_notifier.dart` import the receipt feature's provider file to obtain
`settingsBoxProvider` (`TAIDY-A02`, issue #59). Infrastructure providers for Hive boxes are declared in
`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart` rather than in `core`.

```
            intended                                   observed (partial)

   features ----> core                          features ----> core
       |                                            ^            |
       v                                            +------------+
   domain <---- data                       core/sync, core/theme and core/services
                                           import feature providers and models
```

## 3. Bootstrap Sequence

`main()` in `lib/main.dart` constructs all infrastructure before the widget tree exists, so that
providers can be overridden with already-open resources. The ordering is significant: the encryption
key must exist before any encrypted box is opened, and adapters must be registered before any box is
read.

```
main()
  |
  +-- TelemetryService.instance.initialize(); setupGlobalErrorHandlers()
  +-- dotenv.load('.env')  --fails-->  dotenv.load('.env.example')
  +-- Supabase.initialize(url, anonKey)            (exceptions logged, startup continues)
  +-- Hive.initFlutter()
  +-- SecureStorageService.getHiveEncryptionKey()  -> Uint8List (32 bytes) -> HiveAesCipher
  +-- Hive.registerAdapter(...) x 12
  +-- HiveMigrationService.openBoxSafe('settings')                 (no cipher)
  |     +-- runSchemaMigrations(settingsBox, cipher: cipher)       (target schema version 2)
  +-- HiveMigrationService.openBoxSafe<T>(name, encryptionCipher: cipher) for
  |     receipts_v3, sync_queue, assets, boxes, invoices, sync_outbox
  |        on SchemaCorruptionException --> runApp(_DataRecoveryApp) and return
  +-- _migrateSecretsToSecureStorage(settingsBox)
  +-- runApp(ProviderScope(overrides: [...], child: TAIdyApp()))
        |
        +-- first frame: modelUpdateServiceProvider.checkForUpdates()
                         llmServiceProvider.initialize(); isLlmLoadedProvider = isModelLoaded
                         ref.read(syncManagerProvider)  (instantiates connectivity-driven sync)
```

Design rationale:

- **Open before build.** Opening boxes asynchronously in `main` avoids asynchronous providers for
  every repository; all box providers are synchronous `Provider<Box<T>>` overrides.
- **Recovery shell instead of reset.** A failed box open produces a dedicated `MaterialApp`
  (`_DataRecoveryApp`) rather than deleting data, because Hive's default recovery truncates unreadable
  frames. The current recovery path cannot complete (`TAIDY-H07`, issue #12).
- **Fallback configuration.** Loading `.env.example` when `.env` is absent allows CI and first-time
  builds to start; it also bundles configuration into the binary (`TAIDY-M14`, issue #36).

## 4. State Management and Dependency Injection

### 4.1 Mechanism

Riverpod 2 (`flutter_riverpod`) provides both dependency injection and observable state. Services are
exposed as `Provider<T>`, mutable collections as `StateNotifierProvider<N, S>`, and flags as
`StateProvider<T>`. Riverpod was chosen over a service locator because provider dependencies are
explicit (`ref.watch`) and can be overridden per test with `ProviderScope(overrides: ...)`.

### 4.2 Providers overridden in `main`

These providers throw `UnimplementedError` unless overridden; consumers that tolerate their absence
wrap `ref.watch` in `try/catch` (`TAIDY-A04`, issue #61).

| Provider | Type | Value supplied by `main` |
|---|---|---|
| `hiveBoxProvider` | `Provider<Box<ReceiptModel>>` | box `receipts_v3` |
| `settingsBoxProvider` | `Provider<Box>` | box `settings` |
| `syncBoxProvider` | `Provider<Box<SyncItemModel>>` | box `sync_queue` |
| `assetsBoxProvider` | `Provider<Box<AssetModel>>` | box `assets` |
| `boxesHiveBoxProvider` | `Provider<Box<BoxModel>>` | box `boxes` |
| `invoicesHiveBoxProvider` | `Provider<Box<InvoiceModel>>` | box `invoices` |
| `outboxHiveBoxProvider` | `Provider<Box<SyncOutboxItem>>` | box `sync_outbox` |
| `themeProvider` | `StateNotifierProvider<ThemeNotifier, ThemeMode>` | `ThemeNotifier(settingsBox)` |

### 4.3 Principal providers

| Provider | Type | Depends on |
|---|---|---|
| `receiptRepositoryProvider` | `Provider<ReceiptRepository>` | local data source, `aiServiceProvider`, Supabase data source, settings box, `syncServiceProvider`, webhook service, assets box, `outboxServiceProvider` |
| `receiptListProvider` | `StateNotifierProvider<ReceiptListNotifier, AsyncValue<List<Receipt>>>` | `receiptRepositoryProvider` |
| `filteredReceiptsByActiveBoxProvider` | `Provider<AsyncValue<List<Receipt>>>` | `receiptListProvider`, `activeBoxIdProvider` |
| `aiServiceProvider` | `Provider<AIService>` | `isVlmReadyProvider`, `isLlmLoadedProvider`, settings box, `geminiApiKeyProvider` |
| `boxesProvider` | `StateNotifierProvider<BoxesNotifier, List<BoxModel>>` | boxes box, `outboxServiceProvider` |
| `invoicesProvider` | `StateNotifierProvider<InvoicesNotifier, List<InvoiceModel>>` | invoices box, settings box, `outboxServiceProvider` |
| `assetListProvider` | `StateNotifierProvider<AssetNotifier, List<AssetModel>>` | assets box, `outboxServiceProvider` |
| `outboxServiceProvider` | `Provider<OutboxService>` | `outboxHiveBoxProvider` |
| `syncManagerProvider` | `Provider<SyncManager?>` | Supabase client, outbox, five boxes |
| `syncServiceProvider` | `Provider<SyncService>` | sync queue box, local data source, Supabase data source, settings box |
| `syncEngineProvider` | `Provider<SyncEngine>` | remote replica data source, local data source, `syncServiceProvider`, boxes |
| `syncProgressProvider` | `StateNotifierProvider<SyncProgressNotifier, SyncProgressState>` | `syncEngineProvider` |
| `authProvider` | `StateNotifierProvider<AuthNotifier, AuthState>` | `authRepositoryProvider` |
| `routerProvider` | `Provider<GoRouter>` | `routerNotifierProvider`, `authProvider`, `initialSyncCompletedProvider` |

### 4.4 Provider dependency graph (receipt path)

```
 isVlmReadyProvider ---+
 isLlmLoadedProvider --+--> aiServiceProvider --+
 geminiApiKeyProvider -+                        |
 settingsBoxProvider --+                        v
 hiveBoxProvider --> localDataSourceProvider --> receiptRepositoryProvider --> receiptListProvider
 syncBoxProvider --> syncServiceProvider ------>          ^                         |
 outboxHiveBoxProvider --> outboxServiceProvider ---------+                         v
                                                              filteredReceiptsByActiveBoxProvider
```

Because `receiptRepositoryProvider` watches `aiServiceProvider`, any change of AI backend readiness
rebuilds the repository and therefore the receipt list notifier. Operations awaiting the repository
on the disposed notifier then fail (`TAIDY-M04`, issue #26). The recommended structure resolves the AI
service per request rather than at repository construction.

## 5. Local Persistence

### 5.1 Box registry

| Box name | Value type | Cipher | Opened by | Purpose |
|---|---|---|---|---|
| `settings` | dynamic | none | `main.dart` | preferences, counters, flags, dashboard layout, sync watermark |
| `receipts_v3` | `ReceiptModel` | AES | `main.dart` | receipts with embedded `ReceiptItemModel` list |
| `sync_queue` | `SyncItemModel` | AES | `main.dart` | legacy image and label upload queue (`SyncService`) |
| `assets` | `AssetModel` | AES | `main.dart` | eVault assets |
| `boxes` | `BoxModel` | AES | `main.dart` | spending contexts |
| `invoices` | `InvoiceModel` | AES | `main.dart` | invoices |
| `sync_outbox` | `SyncOutboxItem` | AES | `main.dart` | pending remote mutations (`SyncManager`) |
| `taxonomy_config` | `TaxonomyConfigModel` | none | `TaxonomyNotifier` | category hierarchy (key `current_hierarchy`) |

Unencrypted stores are recorded in `TAIDY-M13` (issue #35).

### 5.2 Hive type identifier registry

| typeId | Type | Declared in |
|---|---|---|
| 0 | `ReceiptModel` | `features/receipt_scanning/data/models/receipt_model.dart` |
| 1 | `ReceiptItemModel` | same file |
| 2 | `DashboardWidgetType` (enum) | `features/receipt_scanning/data/models/dashboard_config.dart` |
| 3 | `DashboardItem` | same file |
| 4 | `TaxonomyItemModel` | `features/settings/data/models/taxonomy_model.dart` |
| 5 | `TaxonomyConfigModel` | same file |
| 6 | `SyncItemModel` | `features/receipt_scanning/data/models/sync_item_model.dart` |
| 7 | `AssetModel` | `features/evault/data/models/asset_model.dart` |
| 10 | `BoxModel` | `features/boxes/data/models/box_model.dart` |
| 11 | `InvoiceModel` | `features/invoices/data/models/invoice_model.dart` |
| 12 | `SyncOutboxItem` | `core/sync/models/sync_outbox_item.dart` |
| 13 | `UserProfileModel` | `features/settings/data/models/user_profile_model.dart` |

Identifier 12 is also declared on the `SyncStatus` enum, which is not registered; the collision is
latent until code generation is re-run (`TAIDY-H06`, issue #11). Type identifiers are part of the
on-disk format and must never be reused or renumbered.

### 5.3 Encryption key lifecycle

`SecureStorageService.getHiveEncryptionKey()` returns `Future<Uint8List>`. On first launch it generates
32 random bytes with `Hive.generateSecureKey()`, stores them base64url-encoded under
`taidy_hive_encryption_key` in `flutter_secure_storage` (Android EncryptedSharedPreferences, iOS
Keychain with `first_unlock_this_device`), and returns them. Subsequent launches read the stored value.

The key is kept outside Hive because a key stored next to the data it protects provides no protection
against file-system access. The trade-off is that the key and the data can be separated: platform
backup restores box files without the keystore-bound key, and keychain loss makes every encrypted box
undecryptable. No key-escrow or re-keying mechanism exists.

### 5.4 Schema versioning and safe open

```
             openBoxSafe(name, cipher)
                       |
              Hive.openBox<T>(...)
                 /            \
            success          exception
               |                 |
          return box      backupBoxFile(name) -- copies <dir>/<name>.hive to
                                 |                 <dir>/hive_backups/<name>_backup_<ts>.hive
                                 v
                 throw SchemaCorruptionException(boxName, cause, backupPath?)
                                 |
                    main.dart: runApp(_DataRecoveryApp)
```

`<dir>` is the value of `HiveMigrationService.getHiveDirectory()`: the application documents directory
on mobile and the application support directory on desktop. Hive itself stores boxes in the documents
directory on every non-web platform, so on desktop the backup step does not find the file
(`TAIDY-H07`).

`runSchemaMigrations(Box settingsBox, {HiveCipher? cipher})` reads `schema_version` (default 1) and
applies ordered migrations up to `currentSchemaVersion` (2). Migration v1 to v2 writes `activeBoxId =
'main'` when absent. Migrations must be idempotent because the version is written after the migration
body completes; an interruption re-executes the body.

### 5.5 Stores outside Hive

| Store | Location | Content |
|---|---|---|
| Episodic memory | `<documents>/memory/episodic_memory.db` (SQLite) and `hnsw_rag.bin` | user corrections and 128-dimensional embeddings used as few-shot context |
| Telemetry | `<documents>/logs/telemetry_events.jsonl` | sanitized crash and inference metrics |
| Dataset contributions | `<documents>/dataset_contributions/dataset_contributions.jsonl` | staged training records |
| Exports | `<documents>/expenses_export_<ms>.csv`, `.json`, `invoices_export_<ms>.csv` | user-initiated exports |
| Models | `<documents>/models/*.gguf` | on-device inference models |
| Grammars | `<documents>/grammars/` | generated GBNF grammar for constrained decoding |

## 6. Authentication, Routing and Access Control

### 6.1 Authentication state

`AuthRepositoryImpl` wraps `GoTrueClient`. All operations return `Future<Either<AuthFailure, T>>`; for
example `signInWithEmailPassword(String email, String password, {bool rememberMe = true})` returns
`Future<Either<AuthFailure, User?>>`. On success with remember-me enabled, the refresh token and the
serialized session are additionally written to secure storage.

`AuthNotifier` (state type `AuthState` with `AuthStatus { unknown, authenticated, unauthenticated,
loading }`) restores the session at construction and then follows `onAuthStateChange`:

```
                 construction
                      |
         rememberMe? -+- no --> clearPersistedSession() --> unauthenticated
                      |
                     yes
                      |
       persisted session present? -- no --> currentUser != null ? authenticated : unauthenticated
                      |
                     yes --> recoverSession() --> success: authenticated
                                                  failure: currentUser != null ? authenticated
                                                                               : unauthenticated

 events: signedIn | tokenRefreshed | userUpdated --> authenticated(user)
         signedOut                               --> unauthenticated
         initialSession (session && rememberMe)  --> authenticated
         initialSession (!rememberMe)            --> unauthenticated
 intents: signIn / signUp / signOut / resetPassword set status = loading while pending
```

The Supabase client also persists its session with its own storage; the two persistence paths are
not reconciled (`TAIDY-M06`, issue #28).

### 6.2 Route guard

`routerProvider` builds a `GoRouter` whose `refreshListenable` is `RouterNotifier`, which calls
`notifyListeners()` whenever `authProvider`, `authStateStreamProvider` or
`initialSyncCompletedProvider` changes. The redirect function evaluates, in order:

| Condition | Redirect |
|---|---|
| not authenticated and location not in {`/`, `/login`, `/signup`} | `/login?from=<uri>` (or `/login`) |
| authenticated, initial sync not completed, location is not `/sync_progress` | `/sync_progress?from=<uri>` |
| authenticated and location in {`/`, `/login`, `/signup`}, or on `/sync_progress` after completion | `from` parameter if present and not an auth route, else `/home` |
| otherwise | no redirect |

The guard is reactive rather than imperative so that token expiry, sign-out on another device and
completion of initial synchronization re-evaluate navigation without explicit calls from pages.
`initialSyncCompletedProvider` is held in memory, so every cold start passes through
`/sync_progress` (`TAIDY-M08`, issue #30).

### 6.3 Biometric guard

`BiometricGuard` wraps the router output in `MaterialApp.builder` and observes application lifecycle:

```
   +----------+   lifecycle pause    +--------+   resume / Unlock   +-----------+
   | unlocked | -------------------> | locked | ------------------> | prompting |
   +----------+                      +--------+                     +-----+-----+
        ^                                 ^                               |
        |                                 |  authenticate() == false      |
        |                                 +-------------------------------+
        |        authenticate() == true, or canAuthenticate() == false    |
        +-----------------------------------------------------------------+
```

| From | Event | To |
|---|---|---|
| unlocked | `AppLifecycleState.paused`, `inactive` or `hidden` while biometrics are enabled | locked |
| locked | `resumed`, first frame, or the Unlock button | prompting |
| prompting | `canAuthenticate()` returns false | unlocked, without a challenge (`TAIDY-H13`) |
| prompting | `authenticate()` returns true | unlocked |
| prompting | `authenticate()` returns false | locked, with an error message |

The guard is enabled by `biometric_auth_enabled` in the settings box. Its fail-open behaviour and
placement are recorded in `TAIDY-H13` (issue #18).

## 7. Receipt Extraction Subsystem

### 7.1 Contract

All extraction backends implement:

```dart
abstract class AIService {
  Future<Either<Failure, Receipt>> extractReceiptData(
    String imagePath, {
    Map<String, Map<String, List<TaxonomyItem>>>? taxonomy,
  });
}
```

A single contract allows the scan flow to remain unchanged while the backend varies with device
capability, user preference and network availability.

### 7.2 Backend selection

`aiServiceProvider` evaluates its dependencies on every rebuild:

```
isVlmReadyProvider == true ? -----------------> VlmEngineService      (on-device, native)
        | no
isLlmLoadedProvider == true ? ----------------> LLMService            (on-device, OCR + llama_cpp_dart)
        | no
enable_gemini_ai && key present ? ------------> GeminiAIService       (cloud)
        | no
        +------------------------------------> MockAIService          (FallbackAIService)
```

The fallback returns synthetic receipts when OCR is unavailable (`TAIDY-H12`, issue #17). Selection is
implicit and carries no provenance (`TAIDY-A08`, issue #65).

### 7.3 On-device VLM: actor isolate and FFI boundary

Native inference blocks the calling thread for seconds. To keep the UI isolate responsive,
`VlmWorkerIsolate` runs a long-lived isolate that owns the native engine handle; the main isolate
communicates only through `SendPort` messages. A persistent worker (rather than `Isolate.run` per
request) amortizes model loading, which dominates latency for multi-gigabyte GGUF files.

```
 main isolate                           worker isolate                      native library
 ------------                           --------------                      --------------
 VlmEngineService.initialize()
   GrammarGenerator.generateAndSave()
   VlmWorkerIsolate.start(...) --spawn--> _isolateEntryPoint
                               <-SendPort-
                               --_InitCommand-->  VlmFfiBindings.load()
                                                  initEngine(...)  -----------> receipt_engine_init
                               <---- bool ready --                <----------- receipt_engine_t*
 extractReceiptData(path)
   read bytes, few-shot context
   processImage(...) ----------_ProcessImageCommand--> processImage(...) ----> receipt_engine_process_image
                               <------------ String? JSON ------------------- int status + buffer
   jsonDecode -> ReceiptModel -> Receipt
```

Dart signatures at the boundary:

- `Future<bool> VlmWorkerIsolate.start({required String modelPath, String? mmprojPath, String? grammarPath, int nThreads = 4, int nGpuLayers = 0, int nCtx = 2048})`
- `Future<String?> VlmWorkerIsolate.processImage({required Uint8List imageBytes, String? fewShotContext, String? systemPrompt, Duration timeout = const Duration(seconds: 45)})`

C ABI (`native/src/receipt_engine.h`):

| Function | Signature | Returns |
|---|---|---|
| `receipt_engine_init` | `(const char* model_path, const char* mmproj_path, const char* grammar_path, int n_threads, int n_gpu_layers, int n_ctx)` | `receipt_engine_t*` or null |
| `receipt_engine_process_image` | `(receipt_engine_t*, const uint8_t* image_bytes, size_t image_len, const char* few_shot_context, const char* system_prompt, char* output_buffer, size_t max_output_len)` | `0` on success, negative status otherwise |
| `receipt_engine_process_image_streaming` | as above with `receipt_token_callback_t callback, void* user_data` instead of the output buffer | status |
| `receipt_engine_free` | `(receipt_engine_t*)` | void |
| `receipt_engine_get_last_error` | `(const receipt_engine_t*)` | `const char*` owned by the engine |

Grammar-constrained decoding (GBNF) is used so that the model can only emit JSON that matches the
receipt schema, which removes the need for post-hoc repair on this path.

Implementation status: the release library compiles placeholder llama.cpp symbols and crashes on
first inference when a model file exists (`TAIDY-C04`, issue #5); the preprocessed image is not passed
to the model (`TAIDY-A05`, issue #62); teardown contains a use-after-free (`TAIDY-H08`, issue #13).
Until these are resolved, the VLM path should be treated as non-functional.

### 7.4 Legacy LLM and cloud paths

`LLMService` (deprecated) runs ML Kit OCR on the main isolate (platform channels require it) and then
runs `llama_cpp_dart` inside `Isolate.run`, constructing and disposing the model per request so that
no native pointer crosses isolates. `GeminiAIService` sends the image and a taxonomy-aware prompt to
the Gemini API and repairs the response with `JsonParserUtils.extractJsonMap`.

## 8. Synchronization Subsystem

### 8.1 Engines

Three mechanisms replicate data. They were introduced at different times and do not share a lock or a
schema contract (`TAIDY-A01`, issue #58).

| Engine | Location | Trigger | Direction | Conflict policy |
|---|---|---|---|---|
| `SyncManager` | `lib/core/sync/sync_manager.dart` | connectivity change; manual "force sync" | push outbox, then pull deltas for receipts, boxes, invoices, vault assets | version, then `updated_at` (`_shouldRemoteOverwrite`) |
| `SyncService` | `lib/features/receipt_scanning/data/datasources/sync_service.dart` | every `saveReceipt`; connectivity change | push image, label JSON and a receipts row to Supabase Storage and PostgREST (or Google Drive) | none (upsert) |
| `SyncEngine` | `lib/features/sync/data/datasources/sync_engine.dart` | `/sync_progress` after login | pull all rows and storage files | receipts: import if absent; other entities: overwrite |

### 8.2 Outbox model

The outbox decouples user actions from network availability: notifiers commit to Hive and then call

```dart
Future<SyncOutboxItem> enqueue({
  required String entityType,   // 'receipt' | 'box' | 'invoice' | 'asset' | 'taxonomy' | 'profile'
  required String entityId,
  required String mutationType, // 'upsert' (any non-delete value is upserted) | 'delete'
  required Map<String, dynamic> payload,
});
```

Items carry a timestamp that is strictly increasing within one `OutboxService` instance
(microsecond resolution, incremented on collision) so that FIFO order reflects the order of local
actions.

```
            enqueue
               |
               v
          +---------+   push succeeds   +----------------------+
          | pending +------------------>+ deleted from outbox  |
          +----+----+                   +----------------------+
               | push fails
               v
          +---------+   retryCount >= 5 or permanent   +--------------------+
          | failed  +--------------------------------->+ permanently_failed |
          +----+----+                                  +---------+----------+
               | next cycle (backoff ignored by SyncManager)     | retryPermanentlyFailed()
               +-----> pending path                              +------> pending
```

### 8.3 Pull and watermark

`SyncManager._pullDeltas` selects rows with `updated_at > last_synced_at` for each table and applies
them through per-entity `_apply*Delta` methods: rows with `deleted_at` set delete the local record;
otherwise the remote model replaces the local one when `_shouldRemoteOverwrite` holds. The watermark
is the device clock at the end of the cycle (`TAIDY-H03`, issue #8), and the version comparison does
not encode causality (`TAIDY-H04`, issue #9).

## 9. Remote Backend Contract

### 9.1 Tables

| Table | Key | Client writers | Notes |
|---|---|---|---|
| `receipts` | `id TEXT` | `SyncManager` (outbox), `SupabaseDataSourceImpl.uploadTrainingData` | columns `scanned_date`, `transaction_time`; no `date` or `items` column (`TAIDY-C03`, issue #4) |
| `receipt_items` | `id TEXT` | none | trigger `trg_stage_training_item` copies rows into `receipt_training_labels` |
| `boxes` | `id TEXT` | `SyncManager` | `color_hex BIGINT`, `icon_identifier` |
| `invoices` | `id TEXT` | `SyncManager` | |
| `vault_assets` | `id TEXT` | `SyncManager` | entity type `asset` |
| `taxonomies` | `id TEXT`, unique `user_id` | none at present | |
| `user_profiles` | `id UUID` = `auth.users.id` | none at present | no `user_id` column |
| `receipt_training_labels` | `id TEXT` | trigger, `SyncManager._stageTier1TrainingLabels` | readable by every authenticated user (`TAIDY-H01`, issue #6) |

All tables except `user_profiles` and `receipt_training_labels` carry `user_id`, `version`,
`created_at`, `updated_at` and `deleted_at`. The `handle_updated_at` trigger sets `updated_at = now()`
and `version = OLD.version + 1` before every update. Row Level Security restricts each user table to
`auth.uid() = user_id`.

### 9.2 Storage buckets

| Bucket | Public | Path convention | Client usage |
|---|---|---|---|
| `receipt_images` | no | `<uid>/...` | not used by the client |
| `asset_documents` | no | `<uid>/...` | not used by the client |
| `training_data` | yes | `<uid>/images/<receiptId><ext>`, `<uid>/labels/<receiptId>.json` | `SyncService` upload, `SyncEngine` download (`TAIDY-C01`, issue #2) |

### 9.3 Dual-tier intent

The schema distinguishes a confidential tier (per-user tables protected by RLS) from an anonymized
training tier (`receipt_training_labels`, view `ai_training_dataset_v1`). The intent is that model
improvement data can be aggregated without access to user records. The tier boundary is not enforced
at present: the training tier carries `receipt_id` join keys, its policy admits all authenticated
users, and server-side redaction is ineffective (`TAIDY-H01`, `TAIDY-H02`).

## 10. Financial Core

`Money` represents an amount as an integer number of minor units (`int cents`), an ISO 4217 currency
code and a decimal `scale` (default 2). Integer arithmetic avoids binary floating-point
representation error, and `roundIntegerDivision(int numerator, int denominator, {MidpointRounding
rounding = MidpointRounding.toEven})` centralizes rounding so that every division is explicit about its
mode. `CurrencyRatio` stores exchange rates as reduced integer fractions for the same reason.
`TaxEngine.calculateInvoice({required List<TaxableLineItem> items, String currency = 'EUR',
MidpointRounding rounding = MidpointRounding.toEven})` aggregates net amounts per (rate, nature code)
bracket and rounds tax once per bracket, which is the method that avoids per-line rounding drift.

These types are not used by persisted models, which store `double` amounts (`TAIDY-A07`, issue #64),
and the only consumer, `TaxComplianceService`, is unreachable from the UI (`TAIDY-A06`, issue #63).
Rounding of negative values is defective (`TAIDY-M17`, issue #39).

## 11. Cross-Cutting Concerns

### 11.1 Error model

Repositories return `Either<Failure, T>` (package `dartz`) instead of throwing, so that callers handle
failure explicitly at compile time. `Failure` (an `Equatable` with a `message`) has the subtypes
`ServerFailure`, `CacheFailure`, `AIProcessingFailure`, `WebhookFailure`, `ParsingFailure`,
`CsvParsingFailure`, `ModelValidationFailure` and the `AuthFailure` family (`InvalidCredentialsFailure`,
`UserNotFoundFailure`, `EmailAlreadyInUseFailure`, `NetworkFailure`). `ErrorHandler.mapException`
translates platform, Dio and Supabase exceptions into these types for display.

### 11.2 Telemetry and global error handling

`TelemetryService.setupGlobalErrorHandlers()` installs `FlutterError.onError` and
`PlatformDispatcher.instance.onError`. Events are sanitized with `PiiScrubberService` and with path
scrubbing for user directories, kept in a 100-entry ring buffer and appended to a JSON-lines file. No
remote transport is implemented. The asynchronous handler reports every error as handled
(`TAIDY-L04`, issue #49).

### 11.3 Privacy scrubbing

`PiiScrubberService.sanitizeText(String? input)` applies, in order, e-mail, IBAN, payment card, phone and
address patterns. It is applied to training labels staged by `SyncManager`, to records staged by
`DatasetContributionService` and to telemetry strings.
It is not applied to receipt images or to the label files uploaded by `SyncService`.

## 12. System Invariants

The following invariants are intended by the design. The status column records whether revision
`c66e079` maintains them.

| # | Invariant | Status |
|---|---|---|
| I-1 | Every user mutation is durable locally before any network operation is attempted. | Maintained for receipts, boxes, invoices and assets. |
| I-2 | Every local mutation of a synchronized entity produces exactly one outbox item in commit order. | Not maintained: invoice overdue transitions bypass the outbox (`TAIDY-M21`); device-only clearing emits tombstones (`TAIDY-C02`). |
| I-3 | A remote row is applied locally only if it is causally newer than the local state. | Not maintained (`TAIDY-H04`, `TAIDY-H05`). |
| I-4 | Every row committed on the server is eventually observed by every device. | Not maintained (`TAIDY-H03`, `TAIDY-H05`). |
| I-5 | The serialized payload of an entity matches the column set of its remote table. | Not maintained (`TAIDY-C03`, `TAIDY-M03`). |
| I-6 | Hive type identifiers are unique and stable. | Maintained at runtime; violated in annotations (`TAIDY-H06`). |
| I-7 | Financial data at rest is encrypted. | Partially maintained (`TAIDY-M13`). |
| I-8 | Personal data leaves the device only for the user's own tier unless the user has consented. | Not maintained (`TAIDY-C01`, `TAIDY-H17`). |
| I-9 | AI results presented to the user originate from an extraction backend. | Not maintained (`TAIDY-H12`). |
| I-10 | Opening encrypted storage never destroys data without explicit user action. | Maintained; recovery is incomplete (`TAIDY-H07`). |

## 13. Architectural Decision Records

### ADR-001: Local-first persistence in encrypted Hive boxes

- **Context.** Receipts are captured offline; the application must work without an account; financial
  data on a lost device must not be readable.
- **Decision.** Store all working data in Hive boxes encrypted with AES-256 (`HiveAesCipher`), keyed by a
  random key held in the platform keystore.
- **Consequences.** Fast synchronous reads and no server dependency. The key and the data can become
  separated (backup restore, keychain loss), so recovery tooling is required. Hive 2.x is no longer
  maintained (`TAIDY-A09`).

### ADR-002: Non-destructive recovery on box open failure

- **Context.** Schema or key mismatches make `Hive.openBox` throw; deleting the box is the common
  remedy and loses data.
- **Decision.** Back up the raw file and show a recovery shell instead of deleting.
- **Consequences.** No silent loss. A complete recovery path (quarantine and explicit reset) is still
  required (`TAIDY-H07`).

### ADR-003: Reactive route guard

- **Context.** Authentication state changes asynchronously (token refresh, remote sign-out).
- **Decision.** Drive GoRouter redirects from a `ChangeNotifier` bound to Riverpod providers.
- **Consequences.** Navigation always reflects authentication state without page-level checks. Route
  arguments passed through `extra` are lost on reload (`TAIDY-M07`).

### ADR-004: Transactional outbox for remote writes

- **Context.** Network calls made directly from UI actions fail offline and cannot be retried reliably.
- **Decision.** Record each mutation in a persistent FIFO outbox and push it in the background.
- **Consequences.** Offline operation and retry are uniform across entities. Correctness requires
  per-entity ordering, error classification and schema-conformant payloads (`TAIDY-M03`, `TAIDY-C03`).

### ADR-005: Inference in a persistent worker isolate behind a C ABI

- **Context.** On-device models take seconds per request and hundreds of milliseconds to load.
- **Decision.** Host the native engine in a long-lived isolate and expose a minimal C ABI through
  `dart:ffi`.
- **Consequences.** The UI isolate stays responsive and the model is loaded once. Native faults
  terminate the process, so the native layer requires sanitizer-backed tests (`TAIDY-C04`,
  `TAIDY-H08`); isolate lifecycle needs serialization (`TAIDY-H10`).

### ADR-006: Explicit failure values

- **Context.** Exceptions crossing layers were silently swallowed or shown verbatim to users.
- **Decision.** Repositories return `Either<Failure, T>`; presentation maps failures to messages.
- **Consequences.** Failure handling is visible in types. Notifiers must propagate failures to callers
  rather than logging them (`TAIDY-M11`).
