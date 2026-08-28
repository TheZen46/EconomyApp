# tAIdy (EconomyApp) - Architectural Guide & Technical Documentation

## Introduction & Project Objectives
tAIdy (also referred to as EconomyApp) is a modular, scalable personal finance management system designed to assist users in tracking, analyzing, and understanding expenditure patterns through a structured and intuitive approach.

Unlike conventional financial tools that suffer from feature bloat and convoluted interfaces, tAIdy prioritizes architectural clarity, modularity, and data transparency. Each subsystem is engineered for high maintainability, testability, and extensibility. This design serves both as a reliable end-user application and as a reference architecture for clean code practices in real-world Flutter/Dart applications.

Conceptually, the system models financial behavior via structured transaction entities, each enriched with core metadata such as categorization, ISO timestamps, and monetary amounts. These raw data streams are subsequently processed into aggregated metrics and historical trends.

## Architecture & System Design
The architecture of tAIdy strictly adheres to the principle of Separation of Concerns (SoC), orchestrated and bound through Riverpod state management. This design eliminates tight coupling between the presentation layer and underlying business domain rules.

The system pipeline is structured into three primary layers:

- **Presentation Layer (UI)**: Manages UI rendering and user interactions. Contains zero business or calculation logic; it reactively observes state exposed by Riverpod providers and responds to lifecycle updates.
- **Domain & Application Logic Layer**: Serves as the core computational engine. It processes transactions, executes deterministic data transformations, and orchestrates AI-assisted optical character recognition (OCR) pipelines. This layer is entirely decoupled from the UI framework, ensuring comprehensive unit testability.
- **Data Persistence Layer**: Governs storage, retrieval, and synchronization via a hybrid persistence strategy:
  - **Hive (NoSQL)**: Provides local, encrypted persistence (via the eVault subsystem) delivering low-latency, offline-first operations.
  - **Supabase**: Handles remote cloud synchronization, multi-device state consistency, and remote backup persistence.
- **AI & Machine Learning Subsystem**: Dedicated edge inference engine supporting local on-device language models (`llama.cpp`) for privacy-first receipt ingestion, with optional fallback routing to remote inference APIs (e.g., Gemini) when computational constraints require.

The standard execution pipeline follows: `User Input -> Domain Logic -> Persistence -> Aggregation & Analytics -> Reactive UI State`.

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
tAIdy incorporates specialized subsystems to handle critical privacy and runtime performance requirements:

- **Data Privacy Isolation Mode**: Enforces strict local execution. When enabled, all outbound network I/O to cloud endpoints (such as Supabase) is blocked, confining read and write operations strictly to local encrypted Hive boxes.
- **Graceful Degradation for AI Inference**: Edge OCR receipt parsing leverages on-device inference (`llama.cpp`). When battery levels or available host memory reach critical thresholds, the inference subsystem automatically re-routes parsing payloads to cloud endpoints (e.g., Gemini / Groq), preventing out-of-memory terminates and conserving battery life.

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
