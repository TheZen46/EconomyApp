# Release 0.1.3 Technical Documentation & Developer Guide

## Executive Summary
Version 0.1.3 introduces major platform capabilities across machine learning inference, distributed state synchronization, mathematical financial processing, and tax compliance:

1. **On-Device Vision-Language Model (VLM) Subsystem & Native Engine**: Integrates high-performance C++ multimodal receipt parsing, GBNF grammar-constrained decoding, HNSW vector indexing for episodic few-shot retrieval, and subword semantic embeddings.
2. **Conflict-Free Replicated Data Types (CRDT) Engine**: Introduces Hybrid Logical Clocks (HLC), vector clocks, and Last-Write-Wins (LWW) registers to deliver deterministic multi-master state convergence across offline and cloud nodes.
3. **Core Financial & Tax Intelligence**: High-precision fixed-point monetary mathematics, automated sales tax/VAT deduction accounting, bank reconciliation matching algorithms, and financial runway forecasting.
4. **Interactive Spatial UI Components**: Interactive spatial bounding box overlays on receipt captures, modular tax liability nests, needs-vs-wants classification widgets, and financial velocity pulse indicators.
5. **System Telemetry & Performance Monitoring**: Real-time instrumentation of inference latency, frame drop metrics, and synchronization queue health.

---

## Architecture and Subsystem Breakdown

### 1. Vision-Language Model (VLM) & Native Inference Pipeline
* Located in: `lib/core/services/vlm/`, `native/`, `android/app/src/main/cpp/`, `ios/receipt_engine.podspec`

#### How It Works
* **Native C++ Engine (`native/receipt_engine.cpp`)**: Compiled via CMake on Android, Windows, and Linux, and CocoaPods on iOS. Provides cross-platform accelerated bindings for tokenization, image pre-processing, and quantized model execution.
* **Worker Isolate Architecture (`vlm_worker_isolate.dart`)**: Spawns a dedicated background Dart isolate communicating through bi-directional `ReceivePort`/`SendPort` channels to ensure zero frame drops on the main UI thread during heavy inference passes.
* **Grammar-Constrained Decoding (`grammar_generator.dart`)**: Dynamically compiles GBNF (GGML BNF) grammar definitions from Dart data structures. This forces the VLM decoder to generate strictly valid JSON adhering to the `ReceiptModel` schema.
* **Episodic Memory & HNSW Vector Indexing (`episodic_memory_service.dart`, `hnsw_index.dart`)**: Computes subword embeddings (`subword_semantic_embedder.dart`) for merchants and line items, indexing past corrections in an on-device Hierarchical Navigable Small World (HNSW) graph. When a new receipt from a known merchant is scanned, relevant past corrections are retrieved as few-shot prompt context.

#### How to Read and Work on It
* `VlmEngineService`: Primary entry point for application code. Call `processReceiptImage(Uint8List imageBytes)` to trigger OCR and layout extraction.
* `VlmFfiBindings`: Low-level FFI bridge mapping native C symbols (`receipt_engine_init`, `receipt_engine_infer`, `receipt_engine_free`) to Dart function pointers.

#### How to Modify It
* To modify extraction schemas, update the schema definition in `grammar_generator.dart` and rebuild tests in `test/core/services/vlm/`.
* To alter embedding dimensions or similarity metrics, configure `HnswIndex` parameters (`M`, `efConstruction`, cosine vs. Euclidean distance) in `hnsw_index.dart`.

---

### 2. Conflict-Free Replicated Data Types (CRDT) Engine
* Located in: `lib/core/crdt/`

#### How It Works
* **Hybrid Logical Clocks (`hlc.dart`)**: Combines physical wall-clock timestamps with logical sequence counters to guarantee strict monotonic causal ordering across distributed nodes without requiring central NTP clock synchronization.
* **Last-Write-Wins Registers (`lww_register.dart`)**: Encapsulates entity fields with an HLC timestamp. When concurrent updates arrive from multiple devices, the register deterministically selects the update with the highest HLC value.
* **Vector Clocks (`vector_clock.dart`)**: Tracks node state versions to identify causal dependencies and detect concurrent branching.
* **CRDT Synchronization Engine (`crdt_sync_engine.dart`)**: Reconciles local and remote state vectors, generating minimal delta payloads during synchronization passes.

#### How to Read and Work on It
* `ReceiptCrdt`: Wraps `ReceiptModel` instances into CRDT field registers. Inspect `merge(ReceiptCrdt other)` to observe deterministic convergence logic.

#### How to Modify It
* To introduce new replicated entities, wrap fields in `LwwRegister<T>` and implement the `CrdtEntity<T>` interface.
* Test conflict scenarios using `test/core/sync/dual_tier_sync_engine_e2e_test.dart`.

---

### 3. Financial Intelligence, Tax Engine & Bank Reconciliation
* Located in: `lib/core/financial/`, `lib/core/services/tax_compliance_service.dart`, `lib/features/receipt_scanning/data/datasources/`

#### How It Works
* **Fixed-Point Money Mathematics (`money.dart`, `currency_ratio.dart`)**: Replaces standard floating-point representation with integer minor units (cents/micros) to eliminate rounding errors in financial aggregations and currency conversions.
* **Tax Compliance Engine (`tax_compliance_service.dart`, `tax_engine.dart`)**: Evaluates transaction line items against configurable tax jurisdiction rule sets (VAT, sales tax, deductibility brackets). Automatically assigns deductible percentages based on merchant taxonomy.
* **Bank Statement Reconciliation (`bank_reconciliation_service.dart`)**: Employs a multi-pass scoring algorithm comparing imported CSV/OFX bank records against scanned receipts. Matches are scored using fuzzy date proximity windows, amount tolerances, and Levenshtein string distance on merchant descriptions.

#### How to Read and Work on It
* `TaxReportService`: Generates aggregate fiscal reports by querying `tax_compliance_service.dart` over specified tax periods.
* `BankReconciliationService.reconcile(List<BankTransaction> bankFeed, List<ReceiptModel> receipts)`: Returns match confidence tuples (`ReconciliationMatch`).

#### How to Modify It
* Add new regional tax schedules by registering `TaxJurisdictionRule` objects in `tax_engine.dart`.
* Adjust matching weights in `bank_reconciliation_service.dart` (`dateWeight`, `amountWeight`, `merchantWeight`).

---

### 4. Interactive UI & Spatial Overlay Components
* Located in: `lib/features/receipt_scanning/presentation/widgets/`, `lib/features/boxes/presentation/widgets/`

#### How It Works
* **Spatial Box Overlay (`spatial_box_overlay.dart`)**: Renders normalized geometric bounding boxes over high-resolution receipt images. Supports tap-to-focus, gesture panning, and real-time bounding box coordinate editing.
* **The Tax Nest (`the_tax_nest_widget.dart`)**: Displays real-time estimated tax liabilities, deduction reserves, and quarterly payment deadlines.
* **Needs vs. Wants (`needs_vs_wants_widget.dart`)**: Visualizes essential vs. discretionary spending distributions.
* **Financial Velocity Pulse (`pulse_widget.dart`)**: Real-time spending speed indicator with burn rate warnings.

---

### 5. Telemetry & Performance Monitoring
* Located in: `lib/core/services/telemetry_service.dart`

#### How It Works
* **TelemetryService**: Captures frame rendering times, VLM inference duration, CRDT sync merge latencies, and memory footprint metrics.
* Exposes stream providers to surface diagnostics in development overlays and automated integration tests.

---

## Technical Changelog

### Version 0.1.3 - 2026-09-09

#### Machine Learning & Computer Vision
* Implemented cross-platform native C++ engine (`native/receipt_engine.cpp`) with CMake and Podspec configurations.
* Added `VlmEngineService` and `VlmWorkerIsolate` for background-isolated multimodal receipt parsing.
* Built `GrammarGenerator` for GBNF grammar-constrained JSON decoding.
* Implemented on-device episodic memory indexing with `EpisodicMemoryService`, `HnswIndex`, and `SubwordSemanticEmbedder`.
* Added dataset contribution service and receipt annotation utilities in `tool/vlm_pipeline/`.

#### Distributed Synchronization & State Management
* Developed comprehensive CRDT engine featuring `HybridLogicalClock`, `VectorClock`, and `LwwRegister`.
* Implemented `ReceiptCrdt` for multi-master conflict-free synchronization.
* Hardened `SyncEngine` and outbox pipeline with atomic mutex locking and network retry policies.

#### Financial Mathematics & Tax Compliance
* Created fixed-point `Money` and `CurrencyRatio` arithmetic library.
* Implemented `TaxComplianceService`, `TaxEngine`, and `TaxReportService` for automated fiscal classification and report generation.
* Built `BankReconciliationService` for automated bank statement cross-matching.
* Integrated financial burn rate calculation in Boxes domain.

#### Presentation & UI Systems
* Added `SpatialBoxOverlay` for interactive bounding box manipulation over receipt images.
* Implemented `TheTaxNestWidget`, `NeedsVsWantsWidget`, `AchievementsMilestonesWidget`, and `ProjectCardsWidget`.
* Integrated `PulseWidget` for real-time burn rate velocity visualization.

#### Testing & Tooling
* Added comprehensive unit, integration, and E2E test suites across `test/core/vlm/`, `test/core/crdt/`, `test/financial/`, `test/features/boxes/`, and `integration_test/`.
* Added release automation script `tool/build_release.ps1`.
