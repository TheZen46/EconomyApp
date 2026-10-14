# tAIdy (EconomyApp) - Architectural Guide & Technical Documentation

## Introduction & Project Objectives
tAIdy (also referred to as EconomyApp) is a modular, scalable personal finance management system designed to assist users in tracking, analyzing, and understanding expenditure patterns through a structured and intuitive approach.

Unlike conventional financial tools that suffer from feature bloat and convoluted interfaces, tAIdy prioritizes architectural clarity, modularity, and data transparency. Each subsystem is engineered for high maintainability, testability, and extensibility. This design serves both as a reliable end-user application and as a reference architecture for clean code practices in real-world Flutter/Dart applications.

Conceptually, the system models financial behavior via structured transaction entities, each enriched with core metadata such as categorization, ISO timestamps, and monetary amounts. These raw data streams are subsequently processed into aggregated metrics and historical trends.

## Architecture & System Design
The architecture of tAIdy strictly adheres to the principle of Separation of Concerns (SoC), orchestrated and bound through Riverpod state management. This design eliminates tight coupling between the presentation layer and underlying business domain rules.

The system pipeline is structured into three primary layers:

- **Presentation Layer (UI)**: Manages UI rendering and user interactions adhering to the International Klein Blue (IKB) design system with Space Grotesk typography. Features custom shader-painted kinetic visualizers (`KineticSyncProgressBar`), modular customizable widget grids, and zero embedded calculation logic.
- **Domain & Application Logic Layer**: Serves as the core computational engine. It processes transactions, executes deterministic data transformations, orchestrates AI-assisted optical character recognition (OCR) pipelines, and runs the mutex-locked `SyncEngine` for delta replication.
- **Data Persistence & Cross-Device Replication Layer**: Governs storage, retrieval, and multi-device parity via a hybrid persistence strategy:
  - **Hive (NoSQL)**: Provides local, AES-256 encrypted persistence (via the eVault and finance subsystems) delivering low-latency, offline-first operations.
  - **Post-Login Synchronization (`SyncEngine`)**: Fetches remote database entities and receipt attachments upon user login, rehydrating local encrypted Hive storage with retry resilience.
  - **Supabase**: Handles remote cloud authentication, PostgreSQL row-level security, and cloud storage persistence.
- **AI & Machine Learning Subsystem**: Multi-tier extraction engine supporting next-gen on-device Vision-Language Models (VLM), legacy on-device LLMs (`llama.cpp`), and remote cloud APIs (e.g. Gemini), with local heuristic fallback.

The standard execution pipeline follows: `User Input / Login -> Router Guard (/sync_progress) -> Delta Sync -> Persistence -> Aggregation & Analytics -> Reactive UI State`.

For an in-depth breakdown of individual components, cryptographic lifecycle management, schema corruption recovery, and Architecture Decision Records (ADRs), refer to the [Detailed Architecture Documentation](docs/architecture.md).

## Prerequisites & Environment Setup
To compile and execute tAIdy, ensure the development environment meets the following toolchain specifications:

- **Flutter SDK** (version 3.10.4 or higher): Cross-platform UI compilation framework.
- **Dart SDK**: Bundled with Flutter; provides the core language runtime and compiler toolchains.
- **Git**: Required for source control management and repository operations.

### Installation & Build Pipeline

1. **Repository Cloning**
   ```bash
   git clone https://github.com/TheZen46/EconomyApp.git
   cd EconomyApp
   ```
   *Description*: Clones the complete project history and checks out the default branch into the local workspace.

2. **Dependency Resolution**
   ```bash
   flutter pub get
   ```
   *Description*: Resolves and downloads all transitively pinned packages specified in `pubspec.yaml` (including Riverpod, Hive, and edge AI plugins).

3. **Environment Configuration (`.env`)**
   ```bash
   cp .env.example .env
   ```
   *Description*: Instantiates the active runtime environment file from the tracked template. Populate the required environment keys (such as `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `GEMINI_API_KEY`) as necessary.

4. **Application Execution**
   ```bash
   flutter run
   ```
   *Description*: Compiles and executes the application on the detected target device or emulator. Specify targeted platforms directly using the `-d` flag (e.g., `flutter run -d chrome` or `flutter run -d android`).

## Usage Guide
The application architecture is structured to transform raw, unstructured financial inputs into actionable analytics.

When a user incurs an expense, a transaction entity is instantiated (either via manual entry or through AI-assisted receipt ingestion). The domain layer processes this entity, calculates running totals, and allocates the expenditure into designated taxonomy categories.

The following conceptual snippet illustrates transaction persistence within the Domain & Logic Layer using Riverpod and Hive:

```dart
// Conceptual transaction management in the Domain/Application Layer
Future<void> addTransaction(WidgetRef ref, double amount, String category) async {
  // 1. Instantiate the structured domain entity
  final newTransaction = Transaction(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    amount: amount, // Negative values denote outflows (e.g., -20.00)
    category: category,
    date: DateTime.now(),
  );

  // 2. Interact with the decoupled persistence service via Riverpod
  final storageService = ref.read(storageServiceProvider);
  await storageService.save(newTransaction);

  // 3. State update notification
  // The Riverpod reactive state graph detects local database mutations
  // and automatically notifies UI consumers to update charts and balances.
}
```
*Code Overview*: A deterministic unique identifier is generated from the timestamp to prevent entity collision. The `Transaction` object is persisted asynchronously via `storageService`. Through Riverpod's reactive graph, UI consumers observing this state update automatically upon write completion without requiring manual screen invalidation.

## Advanced Architecture & Subsystems
tAIdy incorporates specialized subsystems to handle critical privacy, synchronization, and runtime performance requirements:

- **Initial Replication Engine**: Synchronizes user receipts, boxes, invoices, and assets upon authentication via `SyncEngine`. Pulls missing records, streams binary receipt images from Supabase storage into local storage, and displays real-time progress via a custom kinetic progress visualizer.
- **Data Privacy Isolation Mode**: A switch in Settings that keeps all data on the device. While it is on, cloud synchronization, uploads (training contribution and Google Drive backup), webhooks, Gemini cloud inference and over-the-air model update checks are skipped through a single network policy (`lib/core/privacy/network_policy.dart`); changes stay queued in the local encrypted Hive boxes until it is turned off. Signing in is not blocked. The dashboard privacy toggle is separate and only masks figures on screen. Receipts in boxes marked private are never uploaded for model training.
- **Tiered AI Inference Fallbacks**: Edge OCR receipt parsing resolves inference backends dynamically: active native VLM engine, legacy on-device LLM (`llama.cpp`), user-configured Gemini cloud endpoint, and an offline heuristic fallback, ensuring reliable receipt capture under diverse hardware constraints.

## Troubleshooting & Diagnostics

- **Issue: "Target of URI doesn't exist" or unresolved class definitions.**
  - *Root Cause*: Dart package cache corruption or missing transitively resolved dependencies.
  - *Resolution*: Flush the build cache using `flutter clean`, then execute `flutter pub get` to perform a clean dependency resolution.

- **Issue: White screen or immediate crash upon application startup.**
  - *Root Cause*: Hive database initialization lifecycle failure or premature widget tree attachment.
  - *Resolution*: Ensure asynchronous initialization routines (`Hive.initFlutter()`, secure storage key derivation) resolve before `runApp()`, and confirm `WidgetsFlutterBinding.ensureInitialized()` precedes all async operations in `main()`.

- **Issue: Out-of-Memory (OOM) termination during on-device AI inference.**
  - *Root Cause*: Host RAM saturation during large GGUF quantization model loading via `llama.cpp`.
  - *Resolution*: Check memory diagnostics in logs. On resource-constrained mobile hardware, enable cloud fallback mode to delegate inference to remote endpoints.

- **Issue: Cloud synchronization failure / Authentication errors.**
  - *Root Cause*: Missing or malformed Supabase environment variables in `.env`.
  - *Resolution*: Ensure `.env` exists in the project root, conforms to `.env.example` schema without extraneous whitespace, and contains valid `SUPABASE_URL` and `SUPABASE_ANON_KEY` credentials matching your Supabase project dashboard.
