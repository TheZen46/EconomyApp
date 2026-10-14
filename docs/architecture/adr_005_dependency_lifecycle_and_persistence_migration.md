# ADR 005: Dependency Lifecycle, Persistence Evolution & Automated Maintenance

## Status
Accepted

## Context
A codebase dependency audit (reference: TAIDY-A09, Issue #66) identified several architectural risks in the project's dependency topology:
1. **Unmaintained Persistence Engine**: `hive` (2.2.3) and `hive_flutter` (1.1.0) have received no official releases since 2022. Upstream changes in Dart SDK and analyzer versions can threaten future compilation and runtime compatibility.
2. **Exact Version Pins**: Critical code generation and annotation libraries (`json_annotation: 4.8.1`, `freezed_annotation: 2.4.1`, `freezed: 2.5.2`) were pinned to exact historic versions rather than semantic caret constraints, blocking transitive dependency upgrades.
3. **Cloud AI SDK Evolution**: `google_generative_ai` is monitored as Google transitions toward unified Gen AI client libraries (`google_genai`).
4. **Lack of Automated Dependency Updates**: The repository lacked automated dependency scanning and scheduled update policies.

## Decisions

### 1. Adopt Semantic Caret Constraints
All direct and development dependencies in `pubspec.yaml` now utilize caret (`^`) constraints conforming to Semantic Versioning (SemVer). This permits automated resolution of bugfixes and non-breaking minor versions while preventing unexpected breaking changes:
- `json_annotation: ^4.9.0` (was exact `4.8.1`)
- `freezed_annotation: ^2.4.4` (was exact `2.4.1`)
- `freezed: ^2.5.2` (was exact `2.5.2`)

### 2. Automated Dependency Hygiene with Dependabot
Automated weekly dependency monitoring is configured via `.github/dependabot.yml`:
- **pub ecosystem**: Weekly checks for direct and transitive Dart/Flutter dependencies, grouped into batch pull requests to avoid notification fatigue.
- **github-actions ecosystem**: Monthly checks for CI/CD action versions.
- Every automated update pull request must pass the automated GitHub CI pipeline (`flutter analyze` with 0 issues and `flutter test` with 100% pass rate) before merging.

### 3. Persistence Migration Path (Hive to Hive CE or Encrypted SQLite)
User financial data is currently stored locally in AES-256 encrypted Hive boxes (`receipts_v3`, `boxes`, `invoices`, `assets`, `settings`, `sync_outbox`). To safeguard long-term platform maintainability without risking data loss:

#### Option A: Hive CE (Community Edition) - Primary Near-Term Path
- `hive_ce` is a community-maintained fork of Hive that preserves 100% binary storage compatibility with existing `.hive` file formats.
- Adapters, typeIds (0–13), and box files remain untouched, allowing in-place package replacement without complex data export/import routines.
- Scheduled for phased transition once current Dart SDK analyzer compatibility reaches full release milestone.

#### Option B: Native Encrypted SQLite (SQLCipher) - Long-Term Relational Path
- `sqlite3` (`^2.4.6`) and `sqlite3_flutter_libs` (`^0.5.24`) are already linked in the engine.
- If relational query performance, complex foreign keys, or unified ACID transactions across multi-box ledgers become necessary, a one-time migration routine in `HiveMigrationService` will read all encrypted Hive records and copy them into an encrypted SQLite database via SQLCipher.

### 4. Cloud AI Client SDK Policy
- `google_generative_ai: ^0.4.6` remains the stable, supported client library for Gemini 2.5 Flash in Dart.
- When Google's unified `google_genai` package graduates from experimental status (`0.0.1+1`) to general availability, the `GeminiAIService` datasource will be migrated behind the `AIService` and `AiBackendRegistry` abstractions without impacting domain entities.

## Consequences
- **Positive**: Exact pins no longer block solver resolutions; transitive security patches are received automatically; Dependabot alerts team of outdated or vulnerable packages; a clear migration blueprint exists for local persistence.
- **Verification**: Verified via `flutter pub get`, `dart run build_runner build`, `flutter analyze` (0 issues), and `flutter test` (100% pass across all 673 tests).
