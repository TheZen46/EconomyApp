# Release 0.0.4 Documentation

## Overview
Release 0.0.4 introduces the **Cross-Device File Synchronization Engine**, full **Kinetic Synchronization UI** (`/sync_progress`), state-blocking post-login router guards with deep link preservation, cross-device entity rehydration across Hive encrypted boxes, and universal Web/Mobile byte uploading.

---

## Technical Changelog

### Cross-Device Synchronization Engine
* Built `SyncEngine` with mutex-locking serialization (`Lock()`), ensuring thread-safe reads and writes to encrypted local Hive storage.
* Implemented client-side delta synchronization comparing remote entity hashes, timestamps, and storage metadata (`training_data/<userId>/`) against local caches to download only modified chunks.
* Implemented structured multi-table schema rehydration for `receipts`, `boxes`, `assets`, `invoices`, and `taxonomies`.
* Integrated network monitoring via `connectivity_plus` with automatic pause/resume, exponential backoff with randomized jitter (`2^n + jitter`), and an offline continuation fallback mode (`continueOffline()`).
* Universal binary uploading via `XFile.readAsBytes()` + `uploadBinary` across Web and Native platforms.
* Added graceful degradation for Supabase schema notices (such as `PGRST204` missing `image_path` column).

### Kinetic UI and Visual Feedback
* Engineered `KineticSyncProgressBar` featuring dynamic gradient energy wave shaders, glowing leading edge auras, orbital geometric accents, and Space Grotesk / JetBrains Mono typography.
* Developed `SyncProgressPage` (`/sync_progress`) with dynamic rotating context-aware status messaging and a 4-card live telemetry grid (*Data Replicated*, *Delta Objects*, *Bandwidth*, and *Estimated Time*).
* Added manual "Replicate Cloud Data" trigger to the Sync Center in `SettingsPage`.

### Authentication and Reactive Routing
* Added `/sync_progress` route with centralized post-login state blocking in `app_router.dart`.
* Preserved target deep links (`?from=...`) across authentication and replication flows, automatically routing to the target page upon sync completion.
* Subscribed `RouterNotifier` reactively to `initialSyncCompletedProvider`.

### Testing and Documentation
* Added dedicated test suites for `SyncEngine` (`test/features/sync/sync_engine_test.dart`), `KineticSyncProgressBar` (`test/features/sync/sync_progress_page_test.dart`), and router guardrails (`test/core/routes/app_router_test.dart`).
* Maintained 100% test pass rate across 188 automated tests.
* Updated `docs/architecture.md`, `docs/api_reference.md`, `docs/user_guide.md`, `docs/troubleshooting.md`, `PROJECT.md`, and `README.md`.

---

# Release 0.0.3 Documentation

## Overview
Release 0.0.3 establishes the complete Figma design system implementation, core architectural overhauls, biometric authentication integration, Android Gradle optimization, Supabase synchronization stabilization, and comprehensive test suite additions.

Value metric index: 4.6e+46

---

## Technical Changelog

### Architecture and Core Infrastructure
* Migrated Android application namespace from `com.example.t_aidy` to `com.taidy.finance`.
* Updated Gradle build script (`android/app/build.gradle.kts`) with Java 17 toolchain compatibility, resource shrinking, ProGuard optimizations, and release signing configuration.
* Added `BiometricService` leveraging `local_auth` for cryptographic and biometric hardware authentication.
* Implemented standardized error handling hierarchy with `ErrorHandler` and resilient serialization utilities via `JsonParserUtils`.
* Regenerated Freezed and JSON serialization models for `BoxModel`, `InvoiceModel`, `ReceiptModel`, and `SyncItemModel`.
* Configured web platform compatibility layers to isolate non-web dependencies (`dart:io`, native FFI) through conditional imports.

### UI and Design System
* Completed full user interface overhaul conforming strictly to Figma design tokens and layout specifications.
* Implemented the International Klein Blue (IKB) design system across light and dark theme matrices.
* Redesigned Dashboard module including:
  * Real-time financial Pulse metric card.
  * Milestones progress visualization.
  * Needs vs. Wants classification breakdowns.
  * Interactive spend Activity Heatmap.
  * Tax Nest and Active Invoices summary cards.
  * Interactive Project Cards.
  * Customizable dashboard widget layout editor and top navigation bar.
* Re-engineered Settings module as a modal overlay featuring backdrop blur filters, animated toggles, and inline budget configuration editors.
* Implemented hardware-accelerated animations, pointer hover scaling, and touch feedback via `interactive_hover.dart` and `hover_scale.dart`.

### Data Synchronization and Storage
* Refactored Supabase data sources and synchronization pipeline (`SyncService`, `SupabaseDataSource`) to guarantee atomic transaction syncing and resilient offline-first caching.
* Improved Hive data source migration routines and schema persistence stability.
* Refactored Google Drive and local secure storage drivers.

### Web Platform Stability
* Replaced native `Image.file` invocations with cross-platform byte/network rendering adapters to prevent Web/WASM runtime crashes across `review_page.dart` and `vault_page.dart`.
* Resolved compilation errors in `vault_page.dart`, `boxes_page.dart`, and `box_creator_sheet.dart` for web deployment targets.

### Testing and Quality Assurance
* Expanded automated widget and unit test coverage in `test/core/` and `test/features/`.
* Implemented UI overflow regression tests, responsive layout validation, and mock search query test suites.
* Cleaned codebase of unused imports, unreferenced test scripts, and normalized analyzer rules.

### Documentation
* Created comprehensive system architecture reference document (`docs/architecture.md`).
* Updated `README.md` and user integration guides with technical onboarding specifications.

---

## Release Commit Specification
* **Branch:** `main`
* **Commit Message:** `chore(release): prepare release 0.0.3`
* **Tag:** `v0.0.3`
* **Tag Annotation:** `Release version 0.0.3`
