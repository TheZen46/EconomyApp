# Static Analysis Findings Report: tAIdy (EconomyApp)

| Attribute | Value |
|---|---|
| Repository | TheZen46/EconomyApp |
| Revision analysed | `c66e079fa5504e6d49c1f5114832b99c0566c073` |
| Analysis date | 2026-10-01 |
| Method | Manual static analysis (source reading and cross-layer contract tracing) |
| Findings | 65 |

## 1. Scope and Methodology

The analysis covered every non-generated Dart source file under `lib/` (133 files, 31,216 lines), the native inference engine under `native/` and `android/app/src/main/cpp/`, the Supabase schema and migrations under `supabase/`, the GitHub Actions workflows, the Android Gradle configuration, the platform runner build files, and the existing documentation. Generated files (`*.g.dart`, `*.freezed.dart`) were inspected where they deviate from generator output. Python tooling under `tool/` and the test suite were consulted to confirm intended behaviour but were not audited as product code.

Each finding was established by tracing the concrete code path from its entry point (UI action, provider construction, startup sequence or synchronization trigger) to the persistence or network boundary, and by comparing contracts across layers (Dart serializers against SQL columns, Hive type identifiers against registrations, native return paths against FFI expectations). Line references refer to the revision above.

Limitations: the Flutter and Dart SDKs were not available in the analysis environment, so `flutter analyze`, the test suite and the native build were not executed. Statements about third-party behaviour (PostgREST, PostgreSQL, Supabase defaults, Hive, image_picker, GitHub Actions) reflect documented behaviour of those components and should be confirmed in an integration environment where noted in the finding.

## 2. Severity Definitions

| Severity | Definition |
|---|---|
| Critical | Data loss, disclosure of personal or financial data, or process termination on a primary or default code path. |
| High | Security weakness, silent data corruption under realistic conditions, or failure of a primary feature. |
| Medium | Incorrect behaviour on secondary paths or under specific conditions, resource leaks, or latent defects in shipped modules. |
| Low | Minor defects, hygiene issues, documentation gaps with limited direct impact. |
| Architectural | Structural decisions or couplings that restrict extensibility, testability or correctness of future work. |

## 3. Summary

| Severity | Count |
|---|---|
| Critical | 4 |
| High | 17 |
| Medium | 23 |
| Low | 12 |
| Architectural | 9 |
| Total | 65 |

The most consequential themes are: (1) personal data leaves the device without consent and is served from a public bucket and an over-permissive table policy (TAIDY-C01, TAIDY-H01, TAIDY-H02, TAIDY-H17); (2) the synchronization layer consists of three engines whose contracts disagree with the database schema and with each other, which causes failed pushes, lost updates and silent overwrites (TAIDY-C02, TAIDY-C03, TAIDY-H03, TAIDY-H04, TAIDY-H05, TAIDY-A01); (3) the on-device inference stack ships placeholder native code that crashes or fabricates results, and several fallbacks present synthetic data as AI output (TAIDY-C04, TAIDY-H08 to TAIDY-H12, TAIDY-A05).

Each finding is tracked by a GitHub issue; the Issue column links to it.

| ID | Severity | Component | Title | Issue |
|---|---|---|---|---|
| [TAIDY-C01](#taidy-c01) | Critical | Supabase Storage / Training Upload | Receipt images and labels are uploaded to a public storage bucket for every saved receipt without a consent gate | [#2](https://github.com/TheZen46/EconomyApp/issues/2) |
| [TAIDY-C02](#taidy-c02) | Critical | Settings / Data Management | The "Device Only" clear-data action deletes cloud records through outbox tombstones | [#3](https://github.com/TheZen46/EconomyApp/issues/3) |
| [TAIDY-C03](#taidy-c03) | Critical | Sync / Outbox | Receipt outbox payload does not match the remote receipts schema, so receipt synchronization fails and blocks the queue | [#4](https://github.com/TheZen46/EconomyApp/issues/4) |
| [TAIDY-C04](#taidy-c04) | Critical | Native Engine / receipt_engine.cpp | Release native library compiles a stub llama.cpp API whose batch allocator leaves seq_id null, causing a segmentation fault on first inference | [#5](https://github.com/TheZen46/EconomyApp/issues/5) |
| [TAIDY-H01](#taidy-h01) | High | Supabase / Row Level Security | Training-label table is readable by every authenticated user and through an RLS-bypassing view; missing INSERT policy aborts receipt_items writes | [#6](https://github.com/TheZen46/EconomyApp/issues/6) |
| [TAIDY-H02](#taidy-h02) | High | Supabase / PII Anonymization | anonymize_text() uses \b, which PostgreSQL interprets as a backspace escape, so card-number redaction never matches | [#7](https://github.com/TheZen46/EconomyApp/issues/7) |
| [TAIDY-H03](#taidy-h03) | High | Sync / SyncManager | Delta pull watermark comes from the device clock after the pull and queries are unpaginated, causing lost and truncated updates | [#8](https://github.com/TheZen46/EconomyApp/issues/8) |
| [TAIDY-H04](#taidy-h04) | High | Sync / Conflict Resolution | Last-write-wins resolution degenerates to remote-always-wins and overwrites unsynchronized local edits | [#9](https://github.com/TheZen46/EconomyApp/issues/9) |
| [TAIDY-H05](#taidy-h05) | High | Sync / SyncEngine | SyncEngine rehydration reads non-existent columns, resurrects soft-deleted rows and overwrites local entities without conflict checks | [#10](https://github.com/TheZen46/EconomyApp/issues/10) |
| [TAIDY-H06](#taidy-h06) | High | Persistence / Hive | Hive typeId 12 is declared twice and generated adapters are hand-edited, so regenerating code breaks persistence | [#11](https://github.com/TheZen46/EconomyApp/issues/11) |
| [TAIDY-H07](#taidy-h07) | High | Bootstrap / Encrypted Storage | Hive open failures are unrecoverable because of a recovery loop, a desktop backup path mismatch and unguarded key retrieval | [#12](https://github.com/TheZen46/EconomyApp/issues/12) |
| [TAIDY-H08](#taidy-h08) | High | Native Engine / Lifecycle | receipt_engine_free unlocks a mutex owned by an object it has already deleted (use-after-free) | [#13](https://github.com/TheZen46/EconomyApp/issues/13) |
| [TAIDY-H09](#taidy-h09) | High | VLM / FFI Bindings | processImageStream awaits StreamController.close() before a listener exists and deadlocks when the native call ends without a completion callback | [#14](https://github.com/TheZen46/EconomyApp/issues/14) |
| [TAIDY-H10](#taidy-h10) | High | VLM / Worker Isolate | VLM worker initialization timeout leaks the isolate and the loaded model, and concurrent initialization spawns duplicate workers | [#15](https://github.com/TheZen46/EconomyApp/issues/15) |
| [TAIDY-H11](#taidy-h11) | High | AI / OTA Model Updater | OTA model updater downloads executable model binaries from remote configuration without integrity verification | [#16](https://github.com/TheZen46/EconomyApp/issues/16) |
| [TAIDY-H12](#taidy-h12) | High | AI / Extraction Fallbacks | Fallback extraction paths return fabricated receipts as successful AI results | [#17](https://github.com/TheZen46/EconomyApp/issues/17) |
| [TAIDY-H13](#taidy-h13) | High | Auth / BiometricGuard | Biometric guard fails open and its enable flag is stored in the unencrypted settings box | [#18](https://github.com/TheZen46/EconomyApp/issues/18) |
| [TAIDY-H14](#taidy-h14) | High | Import / CsvParserService | CSV import corrupts European-format amounts, discards transaction sign and assumes USD and month-first dates | [#19](https://github.com/TheZen46/EconomyApp/issues/19) |
| [TAIDY-H15](#taidy-h15) | High | AI / LLMService | Legacy on-device LLM path discards the extracted date and uses millisecond timestamps as receipt identifiers | [#20](https://github.com/TheZen46/EconomyApp/issues/20) |
| [TAIDY-H16](#taidy-h16) | High | AI / Model Repository | Model SHA-256 constants are not genuine digests, so verified downloads are discarded, and no vision projector is provisioned | [#21](https://github.com/TheZen46/EconomyApp/issues/21) |
| [TAIDY-H17](#taidy-h17) | High | Privacy / Isolation Controls | Privacy isolation mode and private boxes do not restrict network I/O or access as documented | [#22](https://github.com/TheZen46/EconomyApp/issues/22) |
| [TAIDY-M01](#taidy-m01) | Medium | Integrations / Webhook | Webhook URL is deleted from settings on every launch by the secret migration routine | [#23](https://github.com/TheZen46/EconomyApp/issues/23) |
| [TAIDY-M02](#taidy-m02) | Medium | Sync / Identifiers | Client-chosen non-unique primary keys collide across tenants in the shared remote tables | [#24](https://github.com/TheZen46/EconomyApp/issues/24) |
| [TAIDY-M03](#taidy-m03) | Medium | Sync / Outbox | Outbox processing has global head-of-line blocking, ignores backoff and routes unknown entity types to the receipts table | [#25](https://github.com/TheZen46/EconomyApp/issues/25) |
| [TAIDY-M04](#taidy-m04) | Medium | State Management / Riverpod | Provider dependency cascade recreates ReceiptListNotifier during in-flight operations, and sync services are never disposed | [#26](https://github.com/TheZen46/EconomyApp/issues/26) |
| [TAIDY-M05](#taidy-m05) | Medium | Bootstrap / Supabase Client | Providers access Supabase.instance.client without guards and startup post-frame tasks have no error handling | [#27](https://github.com/TheZen46/EconomyApp/issues/27) |
| [TAIDY-M06](#taidy-m06) | Medium | Auth / Session Management | AuthNotifier leaks its auth-state subscription, and session persistence bypasses secure storage | [#28](https://github.com/TheZen46/EconomyApp/issues/28) |
| [TAIDY-M07](#taidy-m07) | Medium | Routing / GoRouter | The /review route casts state.extra without validation and crashes on refresh or deep link | [#29](https://github.com/TheZen46/EconomyApp/issues/29) |
| [TAIDY-M08](#taidy-m08) | Medium | Sync / Initial Sync Gate | Post-login initial synchronization performs a full replication on every cold start and blocks entry while offline | [#30](https://github.com/TheZen46/EconomyApp/issues/30) |
| [TAIDY-M09](#taidy-m09) | Medium | Boxes / BoxesNotifier | Deleting a box leaves its receipts referencing a non-existent box and removes them from every dashboard view | [#31](https://github.com/TheZen46/EconomyApp/issues/31) |
| [TAIDY-M10](#taidy-m10) | Medium | Receipt Capture / Image Persistence | Receipt images are referenced at transient image_picker paths and are never copied to durable storage | [#32](https://github.com/TheZen46/EconomyApp/issues/32) |
| [TAIDY-M11](#taidy-m11) | Medium | Receipt Review / ReviewPage | Review save coerces locale-formatted totals to zero, reports failures as success and records unchanged items as corrections | [#33](https://github.com/TheZen46/EconomyApp/issues/33) |
| [TAIDY-M12](#taidy-m12) | Medium | AI / GeminiAIService | Gemini integration targets a retired model, mislabels image MIME types, is incompatible with web and requests currency symbols | [#34](https://github.com/TheZen46/EconomyApp/issues/34) |
| [TAIDY-M13](#taidy-m13) | Medium | Privacy / Data at Rest | Several stores of financial data bypass the encrypted Hive layer | [#35](https://github.com/TheZen46/EconomyApp/issues/35) |
| [TAIDY-M14](#taidy-m14) | Medium | Configuration / Environment | .env is bundled as a Flutter asset, embedding API keys and OAuth client secrets in distributed binaries | [#36](https://github.com/TheZen46/EconomyApp/issues/36) |
| [TAIDY-M15](#taidy-m15) | Medium | Native Build / CMake | Native build assumes AVX2 on all x86_64 targets, and the fallback image decoder fabricates pixels and permits large allocations | [#37](https://github.com/TheZen46/EconomyApp/issues/37) |
| [TAIDY-M16](#taidy-m16) | Medium | CI / GitHub Actions | CI does not fail on analyzer errors or test failures, and the release workflow uses a retired action and falls back to debug signing | [#38](https://github.com/TheZen46/EconomyApp/issues/38) |
| [TAIDY-M17](#taidy-m17) | Medium | Financial Core / Money | Money.roundIntegerDivision mis-rounds negative values, and awayFromZero and allocate() violate their documented contracts | [#39](https://github.com/TheZen46/EconomyApp/issues/39) |
| [TAIDY-M18](#taidy-m18) | Medium | Financial Core / Tax | Tax calculations are inconsistent across modules and treat VAT-inclusive receipt prices as net amounts | [#40](https://github.com/TheZen46/EconomyApp/issues/40) |
| [TAIDY-M19](#taidy-m19) | Medium | CRDT Engine | CRDT engine contains convergence defects (positional item identity, derived totals, HLC regression) and is not integrated | [#41](https://github.com/TheZen46/EconomyApp/issues/41) |
| [TAIDY-M20](#taidy-m20) | Medium | Privacy / Data Deletion | Receipt deletion does not erase non-JPEG images from storage and mixes hard and soft deletes | [#42](https://github.com/TheZen46/EconomyApp/issues/42) |
| [TAIDY-M21](#taidy-m21) | Medium | Invoices / Numbering | Invoice numbers are unique only per device, and automatic overdue transitions are not synchronized | [#43](https://github.com/TheZen46/EconomyApp/issues/43) |
| [TAIDY-M22](#taidy-m22) | Medium | ML Pipeline / Dataset Contribution | Training records contain fabricated tax data, placeholder identifiers and constant correction flags | [#44](https://github.com/TheZen46/EconomyApp/issues/44) |
| [TAIDY-M23](#taidy-m23) | Medium | AI / LLMService | LLMService.generate never completes when the model fails to load and leaks its receive port on cancellation | [#45](https://github.com/TheZen46/EconomyApp/issues/45) |
| [TAIDY-L01](#taidy-l01) | Low | Presentation / Resource Management | TextEditingController instances are not disposed in several pages and dialogs | [#46](https://github.com/TheZen46/EconomyApp/issues/46) |
| [TAIDY-L02](#taidy-l02) | Low | Export / CSV | CSV exports are vulnerable to spreadsheet formula injection | [#47](https://github.com/TheZen46/EconomyApp/issues/47) |
| [TAIDY-L03](#taidy-l03) | Low | Core Utilities / JsonParserUtils | JSON repair heuristics corrupt string content containing "//" or the words True, False and None | [#48](https://github.com/TheZen46/EconomyApp/issues/48) |
| [TAIDY-L04](#taidy-l04) | Low | Observability / TelemetryService | Global error handler suppresses every uncaught asynchronous error and the telemetry log grows without bound | [#49](https://github.com/TheZen46/EconomyApp/issues/49) |
| [TAIDY-L05](#taidy-l05) | Low | Presentation / Diagnostics | User-facing confidence, benchmark and verification indicators are synthetic | [#50](https://github.com/TheZen46/EconomyApp/issues/50) |
| [TAIDY-L06](#taidy-l06) | Low | AI / ModelUpdateService | UpdateState.copyWith cannot clear message or error, leaving stale notifications | [#51](https://github.com/TheZen46/EconomyApp/issues/51) |
| [TAIDY-L07](#taidy-l07) | Low | Repository Hygiene | Repository tracks node_modules, stray artifacts and an orphaned duplicate native engine | [#52](https://github.com/TheZen46/EconomyApp/issues/52) |
| [TAIDY-L08](#taidy-l08) | Low | Sync / SyncService | A dead-lettered upload blocks re-scheduling of the same receipt, and each upload scans every receipt | [#53](https://github.com/TheZen46/EconomyApp/issues/53) |
| [TAIDY-L09](#taidy-l09) | Low | Privacy / PiiScrubberService | PII scrubber over-redacts ordinary text and does not cover personal names | [#54](https://github.com/TheZen46/EconomyApp/issues/54) |
| [TAIDY-D01](#taidy-d01) | Low | Documentation / API Coverage | Public API documentation coverage is 36 percent, with several modules at zero | [#55](https://github.com/TheZen46/EconomyApp/issues/55) |
| [TAIDY-D02](#taidy-d02) | Low | Documentation / Accuracy | Existing documentation diverges from the implementation and from repository style policy | [#56](https://github.com/TheZen46/EconomyApp/issues/56) |
| [TAIDY-D03](#taidy-d03) | Low | Documentation / Operational Contracts | Operational contracts are undocumented (Hive type registry, outbox state machine, remote column mapping, conflict policy, data inventory) | [#57](https://github.com/TheZen46/EconomyApp/issues/57) |
| [TAIDY-A01](#taidy-a01) | Architectural | Sync / Architecture | Three overlapping synchronization subsystems operate on the same stores without a shared contract, and the CRDT engine is not wired in | [#58](https://github.com/TheZen46/EconomyApp/issues/58) |
| [TAIDY-A02](#taidy-a02) | Architectural | Layering / Dependency Graph | Core modules depend on feature modules, producing cyclic dependencies | [#59](https://github.com/TheZen46/EconomyApp/issues/59) |
| [TAIDY-A03](#taidy-a03) | Architectural | Data Contracts / Serialization | No single serialization contract exists between Dart models and the remote schema; at least seven hand-written mappers diverge | [#60](https://github.com/TheZen46/EconomyApp/issues/60) |
| [TAIDY-A04](#taidy-a04) | Architectural | Dependency Injection | Static singletons and exception-driven provider wiring impede testing and substitution | [#61](https://github.com/TheZen46/EconomyApp/issues/61) |
| [TAIDY-A05](#taidy-a05) | Architectural | Native Engine / Integration | On-device VLM pipeline is not integrated end to end | [#62](https://github.com/TheZen46/EconomyApp/issues/62) |
| [TAIDY-A06](#taidy-a06) | Architectural | Codebase Structure | Financial, tax, reconciliation and CRDT modules are unreachable from the application | [#63](https://github.com/TheZen46/EconomyApp/issues/63) |
| [TAIDY-A07](#taidy-a07) | Architectural | Financial Core / Monetary Representation | Monetary amounts are persisted and computed as double while the fixed-point Money type is unused | [#64](https://github.com/TheZen46/EconomyApp/issues/64) |
| [TAIDY-A08](#taidy-a08) | Architectural | AI / Backend Selection | AI backend selection is an implicit reactive cascade without capability negotiation, consent or provenance | [#65](https://github.com/TheZen46/EconomyApp/issues/65) |
| [TAIDY-A09](#taidy-a09) | Architectural | Dependencies | Core dependencies are unmaintained, deprecated or pinned to old exact versions | [#66](https://github.com/TheZen46/EconomyApp/issues/66) |

## 4. Findings

### 4.1 Critical

#### TAIDY-C01

**Receipt images and labels are uploaded to a public storage bucket for every saved receipt without a consent gate**

| Attribute | Value |
|---|---|
| Severity | Critical |
| Component | Supabase Storage / Training Upload |
| Tracking issue | [#2](https://github.com/TheZen46/EconomyApp/issues/2) |
| Locations | `supabase/migrations/20260828_master_sync_schema.sql:506-508`<br>`supabase/schema.sql:506-508`<br>`lib/features/receipt_scanning/data/datasources/supabase_data_source.dart:79-198`<br>`lib/features/receipt_scanning/data/repositories/receipt_repository_impl.dart:76-78`<br>`lib/features/receipt_scanning/data/datasources/sync_service.dart:204-228` |

**Root cause analysis.** ReceiptRepositoryImpl.saveReceipt schedules SyncService.scheduleUpload for every saved receipt. SyncService._uploadItem calls SupabaseDataSourceImpl.uploadTrainingData unless the Google Drive toggle is enabled. That method uploads the raw image bytes and a JSON label containing merchant, total, currency, date and every line item to the training_data bucket, obtains a URL with getPublicUrl, and writes it into receipts.image_url. The migration creates training_data with public = true.

The bucket that holds Tier-1 training material is declared public. Objects in public buckets are served through /storage/v1/object/public/ without evaluating storage.objects RLS policies for reads, so the per-user folder policy only constrains writes. The upload path is not gated by any consent setting; the only branch selects between Supabase and Google Drive. Images are raw pixels and are not subject to PII scrubbing. When no user is authenticated the code falls back to a shared images/ and labels/ prefix.

**Observed or potential failure mode.** Any party holding an object URL (persisted in receipts.image_url, in label JSON files, in logs or in exports) can download the receipt image and label without authentication. Receipt images routinely contain merchant identity and address, timestamps, partial card numbers, loyalty identifiers and occasionally customer names. The upload happens for all signed-in users regardless of opt-in, which contradicts the privacy statements in README.md and the Dual-Tier model described in lib/core/sync/sync_manager.dart.

**Mitigation strategy.**

1. Add a migration that sets `public = false` on training_data and revoke anonymous read access; replace getPublicUrl with createSignedUrl (short TTL) where a URL is required, and stop persisting URLs in receipts.image_url.
2. Store user-owned receipt images in the existing private receipt_images bucket (per-user folder policy already exists) and keep the training corpus separate.
3. Gate every training upload behind an explicit, persisted and revocable consent flag (default off) evaluated in SyncService before uploadTrainingData is called.
4. Exclude raw images from the training corpus unless consent explicitly covers images; scrub label text with PiiScrubberService.
5. Abort the upload when no authenticated user exists instead of writing to a shared prefix.
6. Inventory and remove or re-scope objects already uploaded to the public bucket.

#### TAIDY-C02

**The "Device Only" clear-data action deletes cloud records through outbox tombstones**

| Attribute | Value |
|---|---|
| Severity | Critical |
| Component | Settings / Data Management |
| Tracking issue | [#3](https://github.com/TheZen46/EconomyApp/issues/3) |
| Locations | `lib/features/settings/presentation/pages/settings_page.dart:994-1013`<br>`lib/features/receipt_scanning/data/repositories/receipt_repository_impl.dart:139-171`<br>`lib/core/sync/sync_manager.dart:114-119`<br>`lib/core/sync/sync_manager.dart:216-223` |

**Root cause analysis.** The Clear All Data dialog offers "Device Only" (includeCloud: false) and "Everywhere" (includeCloud: true). ReceiptRepositoryImpl.clearAllData skips direct Supabase deletion when includeCloud is false, but enqueues a delete outbox mutation for every local receipt id unconditionally before clearing the local box.

The tombstone enqueue loop is outside the includeCloud branch. SyncManager._flushOutbox translates delete mutations into UPDATE ... SET deleted_at = now() on the remote table, and other devices delete their local copies when they pull rows with deleted_at set (_applyReceiptDelta).

**Observed or potential failure mode.** A user who selects "Device Only" to reset a device or free storage soft-deletes every receipt in the cloud on the next synchronization cycle, and every other signed-in device deletes its local copy on its next pull. No client path restores soft-deleted rows, so the loss is permanent from the user's perspective even though the rows remain in the database.

**Mitigation strategy.**

1. Enqueue delete tombstones only when includeCloud is true.
2. For device-only clearing, remove pending outbox entries for the cleared entities (otherwise pending upserts recreate them) and reset last_synced_at so that a later synchronization performs a full pull.
3. State the exact semantics of both options in the dialog text.
4. Add a regression test asserting that clearAllData(includeCloud: false) enqueues no delete mutation.

#### TAIDY-C03

**Receipt outbox payload does not match the remote receipts schema, so receipt synchronization fails and blocks the queue**

| Attribute | Value |
|---|---|
| Severity | Critical |
| Component | Sync / Outbox |
| Tracking issue | [#4](https://github.com/TheZen46/EconomyApp/issues/4) |
| Locations | `lib/features/receipt_scanning/data/models/receipt_model.dart:75-142`<br>`lib/core/sync/sync_manager.dart:98-138`<br>`lib/core/sync/sync_manager.dart:216-231`<br>`supabase/migrations/20260828_master_sync_schema.sql:45-62`<br>`supabase/migrations/20260828_master_sync_schema.sql:84-137` |

**Root cause analysis.** Receipt mutations are enqueued with payload ReceiptModel.toJson(), which emits `date` and `items` in addition to valid columns. SyncManager upserts the payload unchanged (plus user_id) into public.receipts. The schema defines scanned_date and transaction_time but has no `date` or `items` column; line items belong to public.receipt_items, which no client code writes.

No single schema contract governs the Dart serializer and the SQL schema. PostgREST rejects request bodies that contain columns absent from the target relation (error PGRST204, which supabase_data_source.dart already anticipates for image_path/image_url). On the pull side ReceiptModel.fromJson reads `items` from the row and returns an empty list because the column does not exist.

**Observed or potential failure mode.** Against a database provisioned from supabase/schema.sql or the master migration: every receipt upsert fails; markFailed increments retry_count and _flushOutbox breaks out of the loop, so the failing receipt at the head of the FIFO blocks all subsequent box, invoice and asset mutations for up to five cycles per item before it is marked permanently_failed. Receipts never reach the cloud through the outbox. Any receipt row created by another path (seed scripts, tooling, a schema variant that accepts the payload) is materialized locally with an empty item list and, under TAIDY-H04, can overwrite a local receipt that has items.

**Mitigation strategy.**

1. Introduce a wire DTO for receipts that maps column-for-column to public.receipts, separate from the Hive model; remove `date` and `items` from the upsert body.
2. Choose one representation for line items (rows in public.receipt_items or a JSONB column added by migration) and write and read it consistently in the same logical mutation.
3. Add a contract test that validates DTO keys against the migration's column list (parse the SQL, or query information_schema in an integration environment).
4. Classify PostgREST 4xx schema errors as permanent, dead-letter the item immediately and continue with unrelated entities (see TAIDY-M03).

#### TAIDY-C04

**Release native library compiles a stub llama.cpp API whose batch allocator leaves seq_id null, causing a segmentation fault on first inference**

| Attribute | Value |
|---|---|
| Severity | Critical |
| Component | Native Engine / receipt_engine.cpp |
| Tracking issue | [#5](https://github.com/TheZen46/EconomyApp/issues/5) |
| Locations | `native/src/receipt_engine.cpp:28-195`<br>`native/src/receipt_engine.cpp:166-180`<br>`native/src/receipt_engine.cpp:334-345`<br>`native/src/receipt_engine.cpp:446-505`<br>`native/CMakeLists.txt:16-35`<br>`android/app/src/main/cpp/CMakeLists.txt:8-26` |

**Root cause analysis.** receipt_engine.cpp includes llama.h only when `__has_include("llama.h")` succeeds. Neither CMake project adds a llama.cpp include directory or links llama/ggml, so the #else branch is always compiled. That branch defines exported extern "C" functions with llama.cpp names: llama_model_load_from_file returns `new int(42)`, llama_sample_token always returns token 2 (end-of-sequence), and llama_batch_init allocates token, pos, n_seq_id and logits but never seq_id.

Placeholder implementations are compiled into production artifacts instead of a test target. execute_grammar_constrained_sampling writes `batch.seq_id[i][0] = 0` (line 341) for every prompt token, dereferencing a null pointer whenever engine->model and engine->ctx are non-null, which is the case whenever the configured model path names an existing file. When the file is absent, receipt_engine_init still reports ready and the fallback branch returns a hard-coded receipt (ESSELUNGA S.P.A., total 11.47 EUR) as a successful result. The stub symbols are exported with default visibility under llama.cpp names; in a process that also loads the llama library shipped with llama_cpp_dart, ELF symbol interposition can bind calls across libraries whose structure layouts differ (llama_model_params and llama_context_params are passed by value).

**Observed or potential failure mode.** On any device where VlmEngineService.initialize locates a model file (qwen2_vl_2b.Q4_K_M.gguf, gemma-2b-it.Q4_K_M.gguf, or mock_model_v2.gguf in the working directory), the first call to receipt_engine_process_image or receipt_engine_process_image_streaming terminates the application with SIGSEGV. Native faults cannot be intercepted by FlutterError.onError or PlatformDispatcher.onError. Where the engine is initialized with a non-existent explicit path, every image yields the same fabricated receipt.

**Mitigation strategy.**

1. Remove the stub API from receipt_engine.cpp. Vendor or fetch llama.cpp (FetchContent or add_subdirectory) and emit `#error` when llama.h is unavailable.
2. Move test doubles to native/test under a separate CMake target.
3. Compile with -fvisibility=hidden and export only receipt_engine_* symbols (version script or explicit visibility attributes).
4. Remove the hard-coded fallback receipt from the production translation unit; return a non-zero status and a descriptive error instead.
5. Port the sampling code to the current llama.cpp sampler-chain API before re-enabling inference.
6. Add a CI job that builds the library and runs process_image against a small real GGUF model under AddressSanitizer.

### 4.2 High

#### TAIDY-H01

**Training-label table is readable by every authenticated user and through an RLS-bypassing view; missing INSERT policy aborts receipt_items writes**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Supabase / Row Level Security |
| Tracking issue | [#6](https://github.com/TheZen46/EconomyApp/issues/6) |
| Locations | `supabase/migrations/20260828_master_sync_schema.sql:294-307`<br>`supabase/migrations/20260828_master_sync_schema.sql:331-376`<br>`supabase/migrations/20260828_master_sync_schema.sql:379-393`<br>`supabase/migrations/20260828_master_sync_schema.sql:489-492`<br>`lib/core/sync/sync_manager.dart:124-168` |

**Root cause analysis.** receipt_training_labels has RLS enabled with a single SELECT policy whose USING clause admits `auth.jwt() ->> 'role' = 'authenticated'`. The view ai_training_dataset_v1 selects from the table. No INSERT policy exists. The trigger function stage_anonymized_training_item (not SECURITY DEFINER) inserts into the table after every INSERT or UPDATE on receipt_items. Each row carries receipt_id, which equals the primary key of the owner's row in public.receipts. SyncManager also inserts labels from the client in _stageTier1TrainingLabels.

The policy conflates the service role with every signed-in user. PostgreSQL views execute with the privileges of the view owner unless created WITH (security_invoker = true) (PostgreSQL 15 and later); Supabase grants SELECT on objects in the public schema to anon and authenticated by default, so the view exposes the table independently of RLS unless privileges are revoked. The trigger runs as the invoking role, and without an INSERT policy the insert is rejected under RLS, which rolls back the enclosing receipt_items statement. The client-side staging additionally tests `itemMap is Map<String, dynamic>`, which is false for nested maps read back from Hive after a restart, and inserts duplicate rows on every receipt update.

**Observed or potential failure mode.** Any account holder, and potentially any holder of the public anon key through the view, can enumerate the training corpus of all users, including prices, categories, merchant strings (whose anonymization is defective, see TAIDY-H02) and receipt_id values that link each label to a specific user's private receipt. Client-side Tier-1 inserts are rejected silently. Any future client write to receipt_items fails.

**Mitigation strategy.**

1. Restrict SELECT on receipt_training_labels to the service role only.
2. Recreate ai_training_dataset_v1 WITH (security_invoker = true) and REVOKE ALL ON it FROM anon, authenticated.
3. Drop receipt_id from the training table or replace it with a salted one-way hash that cannot be joined to receipts.
4. Declare the trigger function SECURITY DEFINER with a fixed search_path, or add a narrowly scoped INSERT policy; remove the duplicate client-side staging path so that a single writer exists.
5. Add SQL tests (pgTAP or migration-time assertions) proving that the authenticated and anon roles cannot read either object.

#### TAIDY-H02

**anonymize_text() uses \b, which PostgreSQL interprets as a backspace escape, so card-number redaction never matches**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Supabase / PII Anonymization |
| Tracking issue | [#7](https://github.com/TheZen46/EconomyApp/issues/7) |
| Locations | `supabase/migrations/20260828_master_sync_schema.sql:315-329`<br>`lib/core/privacy/pii_scrubber_service.dart:12-32`<br>`supabase/seed_dummy_data.sql:44-49` |

**Root cause analysis.** anonymize_text applies regexp_replace with `\b(?:\d[ -]*?){13,19}\b` to redact payment card numbers. The Dart scrubber uses the same pattern, where `\b` denotes a word boundary.

In PostgreSQL Advanced Regular Expressions `\b` is the backspace character-entry escape; word boundaries are written `\y`, `\m` and `\M`. The SQL pattern therefore requires literal backspace characters and does not match ordinary text. The SQL function also omits the IBAN and address rules that the Dart implementation applies, so the two tiers are not equivalent.

**Observed or potential failure mode.** Card numbers in item descriptions or merchant strings (for example the seed value "paid with Card 4532 0150 9988 1234") reach receipt_training_labels unredacted; under TAIDY-H01 these values are readable across tenants. The phone pattern can partially redact some digit runs, which masks the defect during casual testing.

**Mitigation strategy.**

1. Replace `\b` with `\y` (or `\m` / `\M`) in every SQL pattern.
2. Port the IBAN and address rules to SQL, or perform anonymization in exactly one tier and treat the other as a verified secondary control.
3. Add SQL assertions for representative inputs (cards with spaces and dashes, IBAN, e-mail, phone) that run with the migration in CI.

#### TAIDY-H03

**Delta pull watermark comes from the device clock after the pull and queries are unpaginated, causing lost and truncated updates**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Sync / SyncManager |
| Tracking issue | [#8](https://github.com/TheZen46/EconomyApp/issues/8) |
| Locations | `lib/core/sync/sync_manager.dart:79-88`<br>`lib/core/sync/sync_manager.dart:171-214` |

**Root cause analysis.** _pullDeltas filters each table with `updated_at > last_synced_at`, where last_synced_at is written as DateTime.now() on the device after the push and pull steps finish. updated_at is assigned by the server trigger handle_updated_at using the database clock. Each query is a single select without range().

The watermark is not derived from the data that was read. Rows committed on the server between the moment a table was queried and the moment last_synced_at is written fall outside every future delta. Device clock skew shifts the window: a fast clock skips server updates permanently; a slow clock re-reads rows. Unpaginated selects are capped by the PostgREST max-rows setting (1000 by default on Supabase projects).

**Observed or potential failure mode.** Remote edits from other devices are never applied on this device; the first pull for accounts above the max-rows limit materializes only a prefix of each table, and later deltas never backfill the remainder because the watermark has already advanced.

**Mitigation strategy.**

1. Persist a per-table watermark equal to the maximum (updated_at, id) observed in the rows actually applied.
2. Query with `updated_at >= watermark` ordered by (updated_at, id), deduplicate by id, and paginate with range() until a short page is returned.
3. Commit the watermark only after the page has been applied to Hive.
4. Alternatively expose a server-side RPC that returns changes after a server-issued cursor.
5. Add tests with a simulated clock offset and with result sets larger than the page size.

#### TAIDY-H04

**Last-write-wins resolution degenerates to remote-always-wins and overwrites unsynchronized local edits**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Sync / Conflict Resolution |
| Tracking issue | [#9](https://github.com/TheZen46/EconomyApp/issues/9) |
| Locations | `lib/core/sync/sync_manager.dart:65-95`<br>`lib/core/sync/sync_manager.dart:216-291`<br>`lib/features/receipt_scanning/data/models/receipt_model.dart:160-176`<br>`supabase/migrations/20260828_master_sync_schema.sql:13-20` |

**Root cause analysis.** _shouldRemoteOverwrite compares integer versions first and updated_at second. The server trigger sets NEW.version = OLD.version + 1 on every UPDATE, including upserts that resolve to updates. ReceiptModel.fromEntity always sets version = 1 and leaves updatedAt null, so local receipt edits never advance the version. syncAll runs _pullDeltas even when _flushOutbox stopped at a failed mutation.

The version counter is owned by the server rather than the writer, so it does not encode causality between replicas. A null local updatedAt is treated as older than any remote value. The pull step does not consult the outbox for pending local mutations on the same entity.

**Observed or potential failure mode.** Any receipt updated at least once on the server (remote version 2 or higher), or any receipt without a local updatedAt, is overwritten during pull, including when the local copy holds a newer edit still waiting in the outbox (for example because of TAIDY-C03 or a connectivity loss). Combined with TAIDY-C03, a remote row without items replaces a local receipt that has items.

**Mitigation strategy.**

1. Skip applying remote rows for entity ids that have pending outbox mutations, or merge and re-queue.
2. Maintain a writer-owned logical clock per entity (the HLC in lib/core/crdt is a candidate) and send it in the payload.
3. Have the server perform conditional updates that reject stale writes instead of incrementing unconditionally.
4. Always set updatedAt on local mutation.
5. Add tests covering push failure followed by pull for every entity type.

#### TAIDY-H05

**SyncEngine rehydration reads non-existent columns, resurrects soft-deleted rows and overwrites local entities without conflict checks**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Sync / SyncEngine |
| Tracking issue | [#10](https://github.com/TheZen46/EconomyApp/issues/10) |
| Locations | `lib/features/sync/data/datasources/sync_engine.dart:136-160`<br>`lib/features/sync/data/datasources/sync_engine.dart:192-241`<br>`lib/features/sync/data/datasources/sync_engine.dart:397-491`<br>`lib/features/sync/data/datasources/remote_replica_data_source.dart:119-201`<br>`supabase/migrations/20260828_master_sync_schema.sql:45-62`<br>`supabase/migrations/20260828_master_sync_schema.sql:140-156` |

**Root cause analysis.** The initial-sync engine maps rows with private parsers that read `date` (receipts) and `color` / `icon` (boxes), whereas the schema defines scanned_date, color_hex and icon_identifier. RemoteReplicaDataSourceImpl selects all rows without filtering deleted_at. Boxes, assets and invoices are written to Hive unconditionally; receipts are imported only when the id is absent locally.

Duplicate row mappers (see TAIDY-A03) diverged from the model fromJson factories, which read the correct columns. Tombstones, versions, timestamps, keywords and flags are discarded by the reduced mappers.

**Observed or potential failure mode.** On a new device or after reinstall every receipt is re-dated to the moment of synchronization (DateTime.now() fallback), corrupting monthly aggregates, tax reports and warranty calculations; every box loses its color and icon; boxes, assets and invoices deleted on another device reappear; local unsynchronized edits to boxes, assets and invoices are replaced on every cold start (see TAIDY-M08).

**Mitigation strategy.**

1. Replace the private parsers with ReceiptModel.fromJson, BoxModel.fromJson, AssetModel.fromJson and InvoiceModel.fromJson.
2. Filter `deleted_at IS NULL` in the queries, or apply tombstones by deleting locally.
3. Apply the same conflict policy as SyncManager, or consolidate the engines (TAIDY-A01).
4. Add tests that feed rows shaped exactly like the migration's columns.

#### TAIDY-H06

**Hive typeId 12 is declared twice and generated adapters are hand-edited, so regenerating code breaks persistence**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Persistence / Hive |
| Tracking issue | [#11](https://github.com/TheZen46/EconomyApp/issues/11) |
| Locations | `lib/features/receipt_scanning/data/models/sync_item_model.dart:6-19`<br>`lib/core/sync/models/sync_outbox_item.dart:6-7`<br>`lib/features/receipt_scanning/data/models/sync_item_model.g.dart:1-74`<br>`lib/core/sync/models/sync_outbox_item.g.dart:1-5`<br>`lib/main.dart:69-81` |

**Root cause analysis.** The enum SyncStatus is annotated @HiveType(typeId: 12) and SyncOutboxItem is also @HiveType(typeId: 12). The checked-in SyncItemModelAdapter (labelled "GENERATED CODE - DO NOT MODIFY BY HAND") writes status as an integer index and therefore never requires a SyncStatus adapter. sync_outbox_item.g.dart is labelled "MANUAL HIVE ADAPTER". main.dart registers SyncOutboxItemAdapter and no SyncStatusAdapter.

Type identifiers are assigned without a registry, and generated sources were modified manually to work around the collision rather than resolving it.

**Observed or potential failure mode.** Running `dart run build_runner build`, a routine step whenever an annotated model changes, regenerates sync_item_model.g.dart with a SyncStatusAdapter (typeId 12) and an item adapter that writes the enum through that adapter. Registering it throws "There is already a TypeAdapter for typeId 12"; not registering it makes every write to sync_queue throw "Cannot write, unknown type: SyncStatus". Records already on disk store status as an integer and become unreadable by the regenerated adapter.

**Mitigation strategy.**

1. Remove @HiveType from SyncStatus (it is persisted as an integer) or assign it an unused id.
2. Introduce a single typeId registry (constants file) and a unit test that asserts uniqueness across all registered adapters.
3. Restore .g.dart files to generator output, or move hand-written adapters to non-generated files excluded from build_runner.
4. Add a CI step that runs build_runner and fails when it produces a diff.

#### TAIDY-H07

**Hive open failures are unrecoverable because of a recovery loop, a desktop backup path mismatch and unguarded key retrieval**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Bootstrap / Encrypted Storage |
| Tracking issue | [#12](https://github.com/TheZen46/EconomyApp/issues/12) |
| Locations | `lib/main.dart:62-67`<br>`lib/main.dart:83-138`<br>`lib/main.dart:264-271`<br>`lib/core/services/hive_migration_service.dart:61-97`<br>`lib/core/services/hive_migration_service.dart:155-218`<br>`lib/core/services/secure_storage_service.dart:20-31` |

**Root cause analysis.** When a box fails to open, HiveMigrationService copies the .hive file to hive_backups/ and throws SchemaCorruptionException; main.dart shows _DataRecoveryScreen, which instructs the user to restart because "tAIdy will create a fresh database". getHiveDirectory returns getApplicationSupportDirectory on Windows, macOS and Linux, while Hive.initFlutter stores boxes under getApplicationDocumentsDirectory on all non-web platforms. getHiveEncryptionKey is awaited in main without error handling.

The failed box is copied, not moved, and nothing quarantines or deletes it, so the next launch fails identically. The backup routine looks for box files in a different directory on desktop, so backupPath is null there. Key retrieval failures (keystore unavailable, Linux without a Secret Service provider, Android restoring app data through Auto Backup while Keystore-bound keys are not restorable) propagate out of main before runApp. If the key is missing while box files exist, a new key is generated silently and every encrypted box fails to decrypt. openBoxSafe completes its completer only from the inner try/catch, so an error routed to the runZonedGuarded handler leaves the startup future pending.

**Observed or potential failure mode.** Users who encounter any open failure are trapped in a permanent recovery screen; desktop users are told that no backup exists; keystore exceptions produce a blank window at launch without diagnostics; a lost key renders all local data permanently undecryptable while the UI suggests that a restart resolves it; a zone-routed Hive error hangs startup indefinitely.

**Mitigation strategy.**

1. After backup, move the failed box into a quarantine directory and offer an explicit "Start with an empty database" action that calls Hive.deleteBoxFromDisk.
2. Compute the Hive directory once, pass it to Hive.init, and reuse the same path for backups.
3. Wrap key retrieval in try/catch and present a dedicated recovery screen; detect "box files exist but key missing" and explain key loss instead of generating a new key silently.
4. Complete the completer with an error from the zone error handler.
5. Exclude Hive files from Android Auto Backup (android:allowBackup="false" or explicit backup rules).
6. Add tests that run against a temporary directory.

#### TAIDY-H08

**receipt_engine_free unlocks a mutex owned by an object it has already deleted (use-after-free)**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Native Engine / Lifecycle |
| Tracking issue | [#13](https://github.com/TheZen46/EconomyApp/issues/13) |
| Locations | `native/src/receipt_engine.cpp:688-710` |

**Root cause analysis.** receipt_engine_free acquires `std::lock_guard<std::mutex> lock(engine->engine_mutex)`, releases resources and calls `delete engine` inside the same block scope.

The lock_guard destructor runs at the end of the scope, after `delete engine`, and calls unlock() on a mutex located in freed memory. Destroying a std::mutex while it is owned is also undefined behaviour.

**Observed or potential failure mode.** Heap corruption or a crash on every engine teardown (VlmWorkerIsolate.stop, VlmEngineService.unload, model switching). The effect is allocator-dependent and can surface later as unrelated memory corruption.

**Mitigation strategy.**

1. Restrict the guard to the resource-release block and delete the engine after the guard has been destroyed: `{ std::lock_guard<std::mutex> g(engine->engine_mutex); /* release */ } delete engine;`.
2. Document that callers must guarantee no concurrent use during free.
3. Build native_engine_test with AddressSanitizer in CI.

#### TAIDY-H09

**processImageStream awaits StreamController.close() before a listener exists and deadlocks when the native call ends without a completion callback**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | VLM / FFI Bindings |
| Tracking issue | [#14](https://github.com/TheZen46/EconomyApp/issues/14) |
| Locations | `lib/core/services/vlm/vlm_ffi_bindings_ffi.dart:319-380`<br>`lib/core/services/vlm/vlm_worker_isolate_ffi.dart:171-215`<br>`lib/core/services/vlm/vlm_worker_isolate_ffi.dart:308-335`<br>`native/src/receipt_engine.cpp:806-845` |

**Root cause analysis.** VlmFfiBindings.processImageStream collects tokens from a synchronous NativeCallable into a single-subscription StreamController, then executes `await controller.close()` when the controller was not closed by the callback, and reaches `yield* controller.stream` only afterwards.

The future returned by close() on a single-subscription controller completes only after the done event has been delivered to a listener; no listener exists until yield* executes, so the await never completes. The native function returns without invoking the callback with is_done = 1 on several paths: image decode failure (return -3), llama_decode failure mid-generation, reaching max_tokens without an end-of-generation token, and the parameter guards.

**Observed or potential failure mode.** The generator suspends permanently; its finally block, which frees the native image buffer and closes the NativeCallable, never runs, leaking both per call; the worker isolate never sends 'done' or 'error'; VlmWorkerIsolate.processImageStream on the main isolate has no timeout, so the scan HUD waits indefinitely. Tokens are also buffered until the native call returns, so the API does not stream.

**Mitigation strategy.**

1. Do not await close() before the stream is consumed; check the native return status and add an error event when it is non-zero.
2. Guarantee in the native implementation that the callback is always invoked with is_done = 1 (scope guard).
3. Apply a timeout on the main-isolate side.
4. For incremental delivery, run the native call on a background thread and deliver tokens with NativeCallable.listener or the existing token ring (receipt_engine_pop_token).

#### TAIDY-H10

**VLM worker initialization timeout leaks the isolate and the loaded model, and concurrent initialization spawns duplicate workers**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | VLM / Worker Isolate |
| Tracking issue | [#15](https://github.com/TheZen46/EconomyApp/issues/15) |
| Locations | `lib/core/services/vlm/vlm_worker_isolate_ffi.dart:77-168`<br>`lib/core/services/vlm/vlm_worker_isolate_ffi.dart:239-257`<br>`lib/core/services/vlm/vlm_engine_service.dart:30-84`<br>`lib/core/services/vlm/vlm_engine_service.dart:95-98`<br>`lib/core/services/vlm/vlm_engine_service.dart:128-133` |

**Root cause analysis.** VlmWorkerIsolate.start spawns an isolate and waits 30 seconds for the initialization reply. VlmEngineService calls initialize() lazily from both extractReceiptData and streamReceiptTokens whenever the worker is not ready.

On timeout the catch block sets _isReady = false but neither terminates the isolate nor clears _isolate and _sendPort, while native initialization continues and retains the model allocation. stop() later kills the isolate with Isolate.immediate, which does not run native destructors, so memory and threads allocated by receipt_engine_init are never released. start() has no mutual exclusion: two concurrent callers both observe _isolate == null, both spawn, and the second assignment orphans the first worker. processImage abandons its reply port after 45 seconds while the worker continues the synchronous native call, so the next request queues behind it.

**Observed or potential failure mode.** Models of 1.3 GB or more that load slowly on mid-range devices exceed 30 seconds, are reported as failures, and remain resident; a retry loads a second copy and the process is terminated for excessive memory use on mobile platforms. Repeated scans produce cascading timeouts.

**Mitigation strategy.**

1. Serialize initialize/start with a lock or a memoized Future.
2. On any start failure, send a dispose command and await its acknowledgement before terminating the isolate.
3. Make timeouts configurable and proportional to model size.
4. Add cooperative cancellation to the native generation loop (atomic flag checked per token) and expose it through the FFI.
5. Reject new requests while one is in flight.

#### TAIDY-H11

**OTA model updater downloads executable model binaries from remote configuration without integrity verification**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | AI / OTA Model Updater |
| Tracking issue | [#16](https://github.com/TheZen46/EconomyApp/issues/16) |
| Locations | `lib/features/receipt_scanning/presentation/providers/model_update_provider.dart:50-136`<br>`lib/features/receipt_scanning/data/repositories/model_repository.dart:152-171`<br>`lib/features/receipt_scanning/data/models/app_config.dart:19-28`<br>`lib/main.dart:334-335` |

**Root cause analysis.** On every launch main.dart calls ModelUpdateService.checkForUpdates, which reads app_config.latest_model_version from Supabase and, when the remote version is newer than a SharedPreferences value, downloads metadata['download_url'] to models/qwen2_vl_v<version>.gguf with Dio.download.

The URL and version are trusted inputs. ModelMetadata.hash exists but is never checked; no scheme or host allow-list is enforced; the version string is interpolated into a file path without validation; the download is not staged. No migration under supabase/ creates the app_config table, so its RLS posture is undefined.

**Observed or potential failure mode.** Whoever can write the app_config row (misconfigured RLS, leaked service key, or a project in which the table is later created without policies) can cause every client to download an arbitrary file into the models directory. GGUF parsers in native inference libraries have a history of memory-safety defects, so a crafted model is a plausible code-execution vector once loaded. A version such as "../../x" writes outside the models directory. Multi-gigabyte downloads start automatically on metered networks. The stored file name never matches the names VlmEngineService searches for, so successful updates are never used.

**Mitigation strategy.**

1. Require a SHA-256 digest, preferably with a detached signature verified against a key pinned in the application, and verify before activation.
2. Restrict download URLs to an allow-list of HTTPS hosts and validate the version against a strict semantic-version pattern.
3. Reuse SupabaseModelRepository.downloadModelWithResume (staged .part file and atomic rename).
4. Require explicit user consent and an unmetered-network check before downloading.
5. Create app_config by migration with read-only access for authenticated users and write access for the service role only.
6. Align the stored file name with the loader's search list.

#### TAIDY-H12

**Fallback extraction paths return fabricated receipts as successful AI results**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | AI / Extraction Fallbacks |
| Tracking issue | [#17](https://github.com/TheZen46/EconomyApp/issues/17) |
| Locations | `lib/features/receipt_scanning/data/datasources/mock_ai_service.dart:18-57`<br>`lib/features/receipt_scanning/data/datasources/mock_ai_service.dart:165-286`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:90-115`<br>`lib/core/services/llm_service_mobile.dart:175-192`<br>`native/src/receipt_engine.cpp:446-505` |

**Root cause analysis.** When neither the VLM nor the legacy LLM is ready and Gemini is disabled (the default configuration), aiServiceProvider returns MockAIService, a FallbackAIService subclass. On desktop, on web, or when ML Kit OCR produces no parsable text, FallbackAIService._parseHeuristically synthesizes a receipt from the file name (for example "Fresh Grocery Supplies" 2 x 18.50 and "Sparkling Mineral Water", or Apple Store items when the name contains "apple"). On non-mobile platforms LLMService.extractTextFromImage returns a fixed "Simulated Receipt Text", and on OCR failure it returns "Error extracting text"; both strings are passed to the model as receipt text.

Demonstration fixtures are wired into production code paths and are indistinguishable from real extraction results; every path returns Right(receipt).

**Observed or potential failure mode.** Users are shown plausible but invented merchants, amounts and items, pre-filled in the review screen. If accepted, fabricated expenses enter the ledger, budgets and reports and, through TAIDY-C01, the training corpus labelled as user-corrected ground truth.

**Mitigation strategy.**

1. Return Left(AIProcessingFailure) when no extraction backend is available and route the user to manual entry.
2. Keep synthetic generators under test/ or behind a debug-only flag that cannot be enabled in release builds.
3. Record the extraction source and confidence on every Receipt so that unverified data can be excluded downstream.
4. In LLMService, abort when OCR fails instead of prompting the model with an error string.

#### TAIDY-H13

**Biometric guard fails open and its enable flag is stored in the unencrypted settings box**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Auth / BiometricGuard |
| Tracking issue | [#18](https://github.com/TheZen46/EconomyApp/issues/18) |
| Locations | `lib/features/auth/presentation/widgets/biometric_guard.dart:38-118`<br>`lib/core/services/biometric_service.dart:11-52`<br>`lib/main.dart:88-92` |

**Root cause analysis.** _authenticate sets `_isAuthenticated = true` when canAuthenticate() returns false, and canAuthenticate returns false on any exception. The flag biometric_auth_enabled is read from the settings box, which is opened without an encryption cipher. When locked, build() returns the lock Scaffold instead of widget.child.

"Cannot authenticate" is treated as "authenticated" instead of falling back to another factor. The setting that controls the guard is stored outside the encrypted storage it is meant to protect. The lock replaces the router subtree rather than overlaying it.

**Observed or potential failure mode.** Removing enrolled biometrics and the device credential, a transient plugin error, or a platform where local_auth is unsupported unlocks the application without a challenge. On desktop and on rooted devices, editing settings.hive to set biometric_auth_enabled to false disables the lock. Each lock discards in-progress page state such as unsaved review edits. On iOS, cancelling the prompt produces a resumed lifecycle event that re-prompts immediately, which yields a prompt loop.

**Mitigation strategy.**

1. Fail closed: when biometric authentication is unavailable, require the account password (Supabase re-authentication) or a local PIN.
2. Store the enable flag in secure storage or in an encrypted box.
3. Render the lock as an overlay so that the navigator subtree and page state are preserved.
4. Suppress automatic re-prompt after an explicit cancel until the user taps Unlock.
5. Obscure application content in the task switcher (FLAG_SECURE on Android, snapshot masking on iOS).

#### TAIDY-H14

**CSV import corrupts European-format amounts, discards transaction sign and assumes USD and month-first dates**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Import / CsvParserService |
| Tracking issue | [#19](https://github.com/TheZen46/EconomyApp/issues/19) |
| Locations | `lib/features/receipt_scanning/data/datasources/csv_parser_service.dart:147-168`<br>`lib/features/receipt_scanning/data/datasources/csv_parser_service.dart:208-246` |

**Root cause analysis.** _tryParseAmount removes every character outside [0-9.-] and parses the remainder; importCsv stores parsedAmount.abs(); currency is fixed to 'USD'; _tryParseDate resolves ambiguous values month-first.

Locale-agnostic normalization deletes the decimal comma; there is no detection of thousands and decimal separators, debit/credit columns, or currency columns; DateTime construction is not validated for overflow.

**Observed or potential failure mode.** "12,50" is imported as 1250.00 and "1.234,56" as 1.23456; refunds and incoming transfers become expenses; all imported receipts are labelled USD; 03/04/2026 becomes 4 March instead of 3 April for European statements; 31/02 rolls over silently to March; re-importing a file duplicates every row. The application's target market (Italian VAT handling, EUR defaults) makes the European format the common case.

**Mitigation strategy.**

1. Detect the decimal separator per column (or let the user select a locale profile) and parse with NumberFormat.
2. Preserve sign; map debits to expenses and credits to income, honouring explicit debit/credit columns.
3. Read a currency column or ask the user.
4. Validate dates by round-tripping components and choose the dominant pattern across the file.
5. Deduplicate by a hash of (date, amount, description).
6. Extend test/features/receipt_scanning/csv_parser_test.dart with European samples.

#### TAIDY-H15

**Legacy on-device LLM path discards the extracted date and uses millisecond timestamps as receipt identifiers**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | AI / LLMService |
| Tracking issue | [#20](https://github.com/TheZen46/EconomyApp/issues/20) |
| Locations | `lib/core/services/llm_service_mobile.dart:146-173` |

**Root cause analysis.** _mapToReceipt builds the Receipt with `date: DateTime.now()` although the prompt requests a date field and the example output contains one; the identifier is DateTime.now().millisecondsSinceEpoch.toString(); currency defaults to EUR and line totals are recomputed from unit price.

Incomplete mapping from the model output to the domain entity, implemented separately from the other AI backends (see TAIDY-A03).

**Observed or potential failure mode.** Every receipt processed by the local LLM is dated at scan time instead of purchase time, which misattributes expenses across months and tax periods. Identifiers collide when two receipts are processed within the same millisecond and are not unique across users (see TAIDY-M02).

**Mitigation strategy.**

1. Parse json['date'] as ISO-8601 with tolerant fallbacks; default to the current date only together with an explicit "date uncertain" flag shown in the review screen.
2. Use UUID v4 identifiers, as the rest of the codebase does.
3. Share one mapping function across all AI backends.

#### TAIDY-H16

**Model SHA-256 constants are not genuine digests, so verified downloads are discarded, and no vision projector is provisioned**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | AI / Model Repository |
| Tracking issue | [#21](https://github.com/TheZen46/EconomyApp/issues/21) |
| Locations | `lib/features/receipt_scanning/data/repositories/model_repository.dart:27-61`<br>`lib/features/receipt_scanning/data/repositories/model_repository.dart:282-299`<br>`lib/core/services/vlm/vlm_engine_service.dart:30-56`<br>`lib/core/services/vlm/vlm_engine_service.dart:70-75` |

**Root cause analysis.** qwen2vl2b.expectedSha256 is c78f921ea345b85a1a1415df8e4d9b62a6e9a65d79901309f7a77b8b40816bf3 and smolVlm500m.expectedSha256 is a19b8f21ca459b73d2a316df8e4d9b62a6e9a65d79901309f7a77b8b40816bf3; the two values share an identical 40-hexadecimal-digit suffix. downloadModelWithResume deletes the .part file when the digest does not match. Qwen2-VL and SmolVLM GGUF deployments require a separate multimodal projector (mmproj) file; no LocalModelInfo describes one and VlmEngineService passes mmprojPath = null. The Gemma entry is a text-only model listed as a VLM candidate.

Placeholder digests were committed as measured values, and the provisioning model treats a vision-language model as a single file.

**Observed or potential failure mode.** Two distinct files sharing 160 bits of SHA-256 output is not a realistic event, so at least one constant, and most likely both, will never match the published file: the user downloads about 1.35 GB, verification fails, the file is deleted and the cycle repeats. With a correct digest the engine would still lack a projector and could not process images (see TAIDY-A05).

**Mitigation strategy.**

1. Pin download URLs to a specific upstream revision rather than `main`, compute digests from those artifacts, and record expected sizes.
2. Add the mmproj artifact with its own digest and require both before enabling the VLM.
3. Add a unit test that rejects duplicate or suffix-sharing digests as a guard against placeholders.
4. Remove text-only models from the VLM candidate list.

#### TAIDY-H17

**Privacy isolation mode and private boxes do not restrict network I/O or access as documented**

| Attribute | Value |
|---|---|
| Severity | High |
| Component | Privacy / Isolation Controls |
| Tracking issue | [#22](https://github.com/TheZen46/EconomyApp/issues/22) |
| Locations | `README.md:94`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:350-375`<br>`lib/features/receipt_scanning/presentation/pages/home_page.dart:545-560`<br>`lib/features/boxes/presentation/widgets/box_creator_sheet.dart:322-328`<br>`lib/core/sync/sync_manager.dart:65-95`<br>`lib/features/receipt_scanning/data/datasources/sync_service.dart:78-154` |

**Root cause analysis.** README.md states that Data Privacy Isolation Mode "enforces strict local execution" and blocks all outbound network I/O to cloud endpoints. privacyModeProvider is read only by dashboard widgets to mask figures. The box editor offers "Private Box (requires auth)"; BoxModel.isPrivate is persisted and synchronized but no code path reads it to restrict access, synchronization or training upload.

The controls were implemented as presentation toggles while the documentation and UI labels describe data-flow controls.

**Observed or potential failure mode.** Users who enable privacy mode or mark a box private continue to have receipts, images and labels uploaded (including to the public bucket described in TAIDY-C01), webhooks fired and remote synchronization performed; private boxes are viewable without additional authentication.

**Mitigation strategy.**

1. Either implement the documented behaviour (a single network policy gate consulted by SyncManager, SyncService, SyncEngine, WebhookService, GeminiAIService and ModelUpdateService; per-box exclusion from upload and training; re-authentication before showing private boxes) or correct the README and UI labels to describe display masking only.
2. Add tests asserting that no network client is invoked while isolation mode is active.

### 4.3 Medium

#### TAIDY-M01

**Webhook URL is deleted from settings on every launch by the secret migration routine**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Integrations / Webhook |
| Tracking issue | [#23](https://github.com/TheZen46/EconomyApp/issues/23) |
| Locations | `lib/main.dart:161-179`<br>`lib/features/settings/presentation/pages/integrations_page.dart:31-57`<br>`lib/features/settings/data/datasources/webhook_service.dart:21-50` |

**Root cause analysis.** _migrateSecretsToSecureStorage runs on every startup and moves gemini_api_key, webhook_secret and webhook_url from the settings box to secure storage, deleting the Hive entries. IntegrationsPage persists the URL to the settings box (comment: "webhook_url and webhook_enabled are non-sensitive: keep in Hive"), and WebhookService reads the URL only from the settings box.

Two modules define contradictory storage contracts for the same key, and the migration is not versioned, so it repeats on every launch.

**Observed or potential failure mode.** After any restart the URL is absent from Hive; sendWebhook returns early without an error; webhook delivery stops silently. The value accumulates in secure storage where nothing reads it. The shared secret is transmitted verbatim in the X-Auth-Secret header, and http:// URLs are accepted.

**Mitigation strategy.**

1. Choose one storage location for the URL (secure storage is appropriate because webhook URLs commonly embed tokens) and use it in IntegrationsPage and WebhookService.
2. Version the secret migration (persist a migration marker) so that it runs once.
3. Reject non-HTTPS URLs and sign payloads with an HMAC over the body and a timestamp instead of sending the secret itself.

#### TAIDY-M02

**Client-chosen non-unique primary keys collide across tenants in the shared remote tables**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Sync / Identifiers |
| Tracking issue | [#24](https://github.com/TheZen46/EconomyApp/issues/24) |
| Locations | `lib/features/boxes/data/providers/boxes_provider.dart:25-43`<br>`lib/core/services/llm_service_mobile.dart:146-149`<br>`lib/core/services/vlm/vlm_engine_service.dart:240-242`<br>`lib/features/receipt_scanning/data/models/receipt_model.dart:102-104`<br>`supabase/migrations/20260828_master_sync_schema.sql:45-47`<br>`supabase/migrations/20260828_master_sync_schema.sql:140-142` |

**Root cause analysis.** Every installation seeds a box with id 'main'. The VLM and LLM paths create receipt identifiers from millisecond timestamps ("vlm_<ms>" and "<ms>"), and ReceiptModel.fromJson falls back to a millisecond identifier. Remote tables declare `id TEXT PRIMARY KEY`, which spans all tenants.

Identifier generation is not globally unique while the remote primary key is global.

**Observed or potential failure mode.** When a second user upserts box 'main' (for example after an edit), INSERT ... ON CONFLICT resolves to an UPDATE of the first user's row, which the RLS USING clause rejects; the mutation fails until it is dead-lettered and blocks the FIFO outbox in the meantime (TAIDY-M03). Millisecond identifiers collide across users and, during batch processing, on a single device.

**Mitigation strategy.**

1. Generate UUID v4 (or v7) identifiers for every entity, including the default box.
2. Keep 'main' only as a local alias that maps to a per-user UUID, or make the remote primary key (user_id, id).
3. Provide a local data migration that rewrites existing identifiers and references (Receipt.boxId, ReceiptItem.boxId, AssetModel.receiptId).

#### TAIDY-M03

**Outbox processing has global head-of-line blocking, ignores backoff and routes unknown entity types to the receipts table**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Sync / Outbox |
| Tracking issue | [#25](https://github.com/TheZen46/EconomyApp/issues/25) |
| Locations | `lib/core/sync/sync_manager.dart:98-138`<br>`lib/core/sync/sync_manager.dart:293-310`<br>`lib/core/sync/outbox_service.dart:47-97`<br>`lib/core/sync/models/sync_outbox_item.dart:11-12` |

**Root cause analysis.** _flushOutbox calls getPendingMutations() without respectBackoff and stops at the first failure. _mapEntityTypeToTable maps unknown values, including the documented 'receipt_item', to 'receipts'. Every payload receives user_id, which user_profiles does not have (its key column is id). retryPermanentlyFailed has no caller.

No distinction between transient and permanent errors; ordering is enforced globally rather than per entity; table routing has a permissive default; payloads are not filtered to the target table's columns.

**Observed or potential failure mode.** One malformed mutation stalls synchronization of all entity types for five cycles; failed items are retried on every connectivity event regardless of backoff; a 'receipt_item' mutation would write an item-shaped row into receipts; profile mutations would always fail; permanently failed items accumulate invisibly.

**Mitigation strategy.**

1. Enforce ordering per (entityType, entityId) instead of globally.
2. Treat PostgREST 4xx responses as permanent and dead-letter immediately; honour backoff for transient errors.
3. Throw on unknown entity types and build payloads from per-table DTOs.
4. Expose permanently failed items and the retry action in the settings UI.

#### TAIDY-M04

**Provider dependency cascade recreates ReceiptListNotifier during in-flight operations, and sync services are never disposed**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | State Management / Riverpod |
| Tracking issue | [#26](https://github.com/TheZen46/EconomyApp/issues/26) |
| Locations | `lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:54-67`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:90-115`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:147-178`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:210-254`<br>`lib/core/sync/sync_providers.dart:25-92`<br>`lib/main.dart:334-338` |

**Root cause analysis.** receiptRepositoryProvider watches aiServiceProvider, which watches isVlmReadyProvider, isLlmLoadedProvider and geminiApiKeyProvider; receiptListProvider watches receiptRepositoryProvider. main.dart sets isLlmLoadedProvider after startup and geminiApiKeyProvider resolves asynchronously. syncServiceProvider and syncManagerProvider construct objects that subscribe to Connectivity().onConnectivityChanged but register no ref.onDispose callback.

The repository captures the AI backend at construction time, which couples the receipt list lifecycle to backend selection; disposable resources are created in providers without teardown.

**Observed or potential failure mode.** When the backend changes (key resolved, model loaded), a new ReceiptListNotifier is created and the previous one is disposed; an addReceipt or deleteReceipt awaiting the repository on the old notifier then assigns state and throws "Tried to use ReceiptListNotifier after dispose", and the list briefly reverts to the loading state. Each recreation of SyncService or SyncManager leaves a live connectivity subscription that continues to trigger synchronization on the orphaned instance.

**Mitigation strategy.**

1. Resolve the AI service at the call site (ref.read in the scan flow) instead of injecting it into the repository.
2. Register ref.onDispose(service.dispose) for SyncService and SyncManager.
3. Check `mounted` after every await in StateNotifier methods before assigning state.

#### TAIDY-M05

**Providers access Supabase.instance.client without guards and startup post-frame tasks have no error handling**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Bootstrap / Supabase Client |
| Tracking issue | [#27](https://github.com/TheZen46/EconomyApp/issues/27) |
| Locations | `lib/main.dart:52-60`<br>`lib/main.dart:330-345`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:122-143`<br>`lib/features/sync/presentation/providers/sync_provider.dart:19-21`<br>`lib/features/auth/data/repositories/auth_repository_impl.dart:11-12` |

**Root cause analysis.** main.dart tolerates Supabase.initialize failures ("deferred/offline mode"), but supabaseDataSourceProvider, modelRepositoryProvider, remoteReplicaDataSourceProvider and AuthRepositoryImpl dereference Supabase.instance.client unconditionally. The post-frame callback in _TAIdyAppState awaits checkForUpdates() and llmService.initialize() without try/catch.

Optional infrastructure is modelled as mandatory in the dependency graph.

**Observed or potential failure mode.** If initialization throws (malformed URL, local storage plugin failure), the receipt repository, authentication and router providers throw on first read and the application becomes unusable despite its offline-first design. An exception in the post-frame callback is reported as fatal by the global handler and the remaining startup steps (LLM readiness flag, SyncManager creation) are skipped.

**Mitigation strategy.**

1. Expose a nullable supabaseClientProvider that reflects initialization state, and make cloud-dependent data sources optional.
2. Degrade to local-only behaviour when the client is unavailable.
3. Wrap each startup task independently with error reporting.
4. Validate SUPABASE_URL format before initialization.

#### TAIDY-M06

**AuthNotifier leaks its auth-state subscription, and session persistence bypasses secure storage**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Auth / Session Management |
| Tracking issue | [#28](https://github.com/TheZen46/EconomyApp/issues/28) |
| Locations | `lib/features/auth/presentation/providers/auth_provider.dart:14-42`<br>`lib/features/auth/presentation/providers/auth_provider.dart:46-134`<br>`lib/features/auth/presentation/providers/auth_provider.dart:236-250`<br>`lib/features/auth/presentation/providers/auth_provider.dart:278-282`<br>`lib/features/auth/data/repositories/auth_repository_impl.dart:24-55`<br>`lib/main.dart:53-57` |

**Root cause analysis.** _initialize calls _repository.authStateChanges.listen(...) and discards the returned subscription; the field _authSubscription, typed StreamSubscription<AuthState> where AuthState resolves to the local class rather than supabase_flutter's, is never assigned. Supabase.initialize is called without custom authOptions, so supabase_flutter persists the session (access and refresh tokens) through its default SharedPreferences-backed storage in addition to the copy written to flutter_secure_storage. When "remember me" is disabled, the notifier purges the secure-storage copy and reports unauthenticated, while the Supabase client restores its own persisted session.

A local class named AuthState shadows the imported type and hides the mismatch; two independent persistence mechanisms exist for the same credential.

**Observed or potential failure mode.** The subscription outlives the notifier, and state assignments after disposal throw. Refresh tokens are stored in plaintext preferences on Android and desktop. With remember-me disabled the UI shows a signed-out state while SyncManager, which checks supabase.auth.currentUser, continues to synchronize under the restored session. A failed signOut leaves status = loading.

**Mitigation strategy.**

1. Assign and cancel the subscription; rename the local class (for example AppAuthState).
2. Configure supabase_flutter with a LocalStorage implementation backed by flutter_secure_storage and remove the duplicate persistence.
3. Call auth.signOut(scope: SignOutScope.local) when remember-me is disabled.
4. Restore a non-loading status when signOut fails.

#### TAIDY-M07

**The /review route casts state.extra without validation and crashes on refresh or deep link**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Routing / GoRouter |
| Tracking issue | [#29](https://github.com/TheZen46/EconomyApp/issues/29) |
| Locations | `lib/core/routes/app_router.dart:180-197` |

**Root cause analysis.** The page builder executes `final receipt = state.extra as Receipt;`.

GoRouter does not persist extra across browser reloads, deep links or state restoration, and the route has no parameter-based fallback.

**Observed or potential failure mode.** Reloading the web application on /review, opening a link to it, or restoring navigation state raises a TypeError and renders an error screen.

**Mitigation strategy.**

1. Accept the receipt identifier as a path parameter (/review/:id) and load the receipt from the repository when extra is absent.
2. Redirect to /home when neither source is available.

#### TAIDY-M08

**Post-login initial synchronization performs a full replication on every cold start and blocks entry while offline**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Sync / Initial Sync Gate |
| Tracking issue | [#30](https://github.com/TheZen46/EconomyApp/issues/30) |
| Locations | `lib/core/routes/app_router.dart:81-97`<br>`lib/features/sync/presentation/providers/sync_provider.dart:66-96`<br>`lib/features/sync/data/datasources/sync_engine.dart:101-160`<br>`lib/features/sync/data/datasources/sync_engine.dart:309-328`<br>`lib/features/sync/data/datasources/remote_replica_data_source.dart:119-132` |

**Root cause analysis.** initialSyncCompletedProvider is an in-memory StateProvider initialised to false, and the router redirects every authenticated session to /sync_progress until it becomes true. SyncEngine fetches every row of four tables and lists storage on each run, with up to five attempts, exponential backoff and 12-second timeouts per query. Fetch errors are converted to empty lists. The "Verifying bit-for-bit directory integrity" stage is a fixed 300 ms delay.

The gate is not persisted, SyncEngine has no delta mode, and data-source errors are swallowed.

**Observed or potential failure mode.** Every launch repeats a full download whose cost grows with data volume; offline launches stop on the progress page until the user selects the offline option; failed queries report "Replication complete" with no data; combined with TAIDY-H05, every cold start re-applies lossy remote state.

**Mitigation strategy.**

1. Persist completion per user and device, and block only on first login.
2. Perform subsequent synchronization in the background through a single engine (TAIDY-A01).
3. Propagate fetch errors so that the retry logic engages.
4. Remove the simulated verification stage or implement an actual checksum comparison.

#### TAIDY-M09

**Deleting a box leaves its receipts referencing a non-existent box and removes them from every dashboard view**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Boxes / BoxesNotifier |
| Tracking issue | [#31](https://github.com/TheZen46/EconomyApp/issues/31) |
| Locations | `lib/features/boxes/data/providers/boxes_provider.dart:98-120`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:180-190`<br>`lib/features/boxes/presentation/widgets/box_creator_sheet.dart:130-135` |

**Root cause analysis.** deleteBox removes the box and resets activeBoxIdProvider to 'main' but does not update receipts whose boxId equals the deleted identifier. filteredReceiptsByActiveBoxProvider shows only receipts whose boxId matches the active box ('main' matches null or 'main').

No referential integrity between receipts and boxes in the local store.

**Observed or potential failure mode.** Receipts disappear from the dashboard, budgets and pulse widgets while still occupying storage and being synchronized; the confirmation dialog does not describe this effect. The call site does not await deleteBox, so errors it rethrows become unhandled.

**Mitigation strategy.**

1. In one operation, reassign affected receipts and their items to 'main' (or delete them after explicit confirmation) and enqueue the corresponding mutations.
2. Await the future at the call site and surface errors.

#### TAIDY-M10

**Receipt images are referenced at transient image_picker paths and are never copied to durable storage**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Receipt Capture / Image Persistence |
| Tracking issue | [#32](https://github.com/TheZen46/EconomyApp/issues/32) |
| Locations | `lib/features/receipt_scanning/presentation/pages/scan_page.dart:149-177`<br>`lib/features/receipt_scanning/data/repositories/receipt_repository_impl.dart:86-105` |

**Root cause analysis.** The XFile path returned by ImagePicker is passed through extraction and persisted as Receipt.imagePath and AssetModel.receiptImagePath.

On Android and iOS image_picker writes captures to the application cache or temporary directory, which the operating system may purge; on web the path is a session-scoped blob URL.

**Observed or potential failure mode.** Warranty evidence in the eVault and receipt thumbnails disappear after cache eviction or reinstall; deferred uploads find no file and proceed with metadata only.

**Mitigation strategy.**

1. At save time, copy the image into an application-documents subdirectory keyed by receipt identifier (encrypted at rest where feasible) and store the relative path.
2. Delete the stored image when the receipt is deleted.
3. On web, persist bytes in IndexedDB or upload immediately to the private bucket.

#### TAIDY-M11

**Review save coerces locale-formatted totals to zero, reports failures as success and records unchanged items as corrections**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Receipt Review / ReviewPage |
| Tracking issue | [#33](https://github.com/TheZen46/EconomyApp/issues/33) |
| Locations | `lib/features/receipt_scanning/presentation/pages/review_page.dart:53-75`<br>`lib/features/receipt_scanning/presentation/pages/review_page.dart:322-366`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:210-226` |

**Root cause analysis.** _saveReceipt computes totalAmount with `double.tryParse(_totalController.text) ?? 0.0`. ReceiptListNotifier.addReceipt logs repository failures and restores the previous state without signalling the caller, and _saveReceipt then navigates to /home. For every item with a mainCategory, recordUserCorrection is called with rawName equal to correctedName. The text controllers are never disposed.

Parsing is not locale-aware; the notifier swallows the error channel; the original AI output is not retained for comparison.

**Observed or potential failure mode.** A user entering "12,50" saves a receipt with total 0.00; storage failures are invisible; episodic memory fills with identity mappings for every saved item, displacing genuine corrections from the few-shot context; controllers leak for every review session.

**Mitigation strategy.**

1. Parse with NumberFormat for the active locale or constrain input with a formatter.
2. Return Either (or throw) from addReceipt and show an error on failure.
3. Diff edited items against widget.receipt.items and record only changed fields, using the original value as rawName.
4. Dispose controllers in dispose().

#### TAIDY-M12

**Gemini integration targets a retired model, mislabels image MIME types, is incompatible with web and requests currency symbols**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | AI / GeminiAIService |
| Tracking issue | [#34](https://github.com/TheZen46/EconomyApp/issues/34) |
| Locations | `lib/features/receipt_scanning/data/datasources/gemini_ai_service.dart:14-33`<br>`lib/features/receipt_scanning/data/datasources/gemini_ai_service.dart:43-90`<br>`lib/features/receipt_scanning/data/datasources/gemini_ai_service.dart:96-114` |

**Root cause analysis.** The service constructs GenerativeModel(model: 'gemini-1.5-flash') through the google_generative_ai package, reads the image with dart:io File, sends every image as DataPart('image/jpeg', ...), and instructs the model to return the currency as a symbol (€, $, £).

Hard-coded model identifier and MIME type; platform-specific file access; a prompt contract that conflicts with the ISO 4217 codes used elsewhere (VARCHAR(3) column, Money, FatturaPA Divisa).

**Observed or potential failure mode.** Google has retired the Gemini 1.5 model family, so requests to gemini-1.5-flash are expected to fail and the cloud tier to be non-functional (confirm against the current model catalogue); the google_generative_ai Dart package is deprecated by its publisher. PNG and HEIC images are mislabelled. On web, File access is unavailable and every extraction fails. Receipts carry symbols such as "€", which breaks currency grouping and ISO-based conversion. Raw responses containing receipt content are written to debug logs.

**Mitigation strategy.**

1. Make the model identifier configurable and move to a supported model and SDK.
2. Detect the MIME type from the file signature (package:mime) and read bytes through XFile.
3. Request ISO 4217 codes and normalise symbols on ingestion.
4. Use the API's structured-output (response schema) feature and stop logging raw responses in release builds.

#### TAIDY-M13

**Several stores of financial data bypass the encrypted Hive layer**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Privacy / Data at Rest |
| Tracking issue | [#35](https://github.com/TheZen46/EconomyApp/issues/35) |
| Locations | `lib/main.dart:88-92`<br>`lib/core/services/vlm/episodic_memory_service_ffi.dart:77-100`<br>`lib/core/services/telemetry_service.dart:252-279`<br>`lib/core/services/export_service.dart:82-95`<br>`lib/core/services/export_service.dart:134-147`<br>`lib/core/services/vlm/dataset_contribution_service.dart:20-33` |

**Root cause analysis.** The settings box stores the monthly budget, current balance, projected income, tax goal, invoice counter, webhook URL and biometric flag, and is opened without encryptionCipher. Episodic memory (merchant names and item corrections) uses an unencrypted SQLite file. Telemetry, dataset contributions and exports are written as plaintext files in the documents directory; exports are never removed and telemetry is never rotated.

Encryption is applied per Hive box rather than as a storage policy covering every persistence mechanism.

**Observed or potential failure mode.** The README's description of encrypted local persistence does not hold for a substantial portion of user data. Device backups, forensic access, or any process with file-system access on desktop obtain balances, merchant histories and complete CSV or JSON exports. Telemetry logs grow without bound.

**Mitigation strategy.**

1. Open the settings box with the cipher, migrating the existing plaintext box once.
2. Use SQLCipher with a key from secure storage for episodic memory.
3. Write exports to a temporary directory and delete them after sharing completes.
4. Rotate telemetry logs by size and age.
5. Document the data inventory and the protection applied to each store.

#### TAIDY-M14

**.env is bundled as a Flutter asset, embedding API keys and OAuth client secrets in distributed binaries**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Configuration / Environment |
| Tracking issue | [#36](https://github.com/TheZen46/EconomyApp/issues/36) |
| Locations | `pubspec.yaml:115-119`<br>`lib/main.dart:37-50`<br>`lib/core/services/google_drive_service.dart:73-90`<br>`.github/workflows/ci.yml:21-22`<br>`.github/workflows/gh-pages.yml:30-31` |

**Root cause analysis.** pubspec.yaml lists .env and .env.example under flutter.assets; main.dart loads .env and falls back to .env.example; GoogleDriveService reads GOOGLE_CLIENT_SECRET from the same source.

Runtime configuration and secrets share one mechanism that copies files verbatim into the application bundle (APK assets, IPA, web build output).

**Observed or potential failure mode.** Any key present in the developer's .env at build time (Gemini API key, Google client secret, webhook secret) is extractable from the published artifact, including the GitHub Pages web build. The .env.example fallback yields a non-empty placeholder Gemini key and Supabase URL, so code that checks for key presence proceeds against invalid endpoints.

**Mitigation strategy.**

1. Supply only public configuration (Supabase URL and anon key) through --dart-define-from-file.
2. Never ship server-side secrets in client builds; proxy Gemini requests through a backend function that holds the key.
3. Treat placeholder values as absent by validating format.
4. Remove .env from the asset list.

#### TAIDY-M15

**Native build assumes AVX2 on all x86_64 targets, and the fallback image decoder fabricates pixels and permits large allocations**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Native Build / CMake |
| Tracking issue | [#37](https://github.com/TheZen46/EconomyApp/issues/37) |
| Locations | `native/CMakeLists.txt:53-75`<br>`android/app/src/main/cpp/CMakeLists.txt:28-50`<br>`native/src/image_preprocessor.cpp:26-158` |

**Root cause analysis.** x86_64 builds add -mavx2 -mfma unconditionally (desktop and Android x86_64) and define __AVX2__, __ARM_NEON and _OPENMP manually. stb_image.h is not vendored, so the stub stbi_load_from_memory returns nullptr and decodeImage falls back to "header inspection": it reads dimensions from the JPEG SOF or PNG IHDR fields (up to 16384 x 16384), allocates width x height x 3 bytes and fills the buffer by repeating the compressed input.

The baseline instruction set is not distinguished from optional acceleration, and a placeholder decoder is part of the production translation unit.

**Observed or potential failure mode.** The library raises SIGILL on x86_64 processors without AVX2 (older desktops, some low-power CPUs, some emulators). Every image is converted into meaningless pixel data. A crafted or corrupted header requests about 805 MB, which can terminate the process on mobile devices.

**Mitigation strategy.**

1. Build for a baseline ISA and dispatch AVX2 kernels at runtime after a CPUID check, or ship separate variants.
2. Remove manual definitions of compiler-reserved macros.
3. Vendor stb_image (or use platform decoders) and fail decoding instead of fabricating data.
4. Cap decoded dimensions to the inference budget and downscale progressively.

#### TAIDY-M16

**CI does not fail on analyzer errors or test failures, and the release workflow uses a retired action and falls back to debug signing**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | CI / GitHub Actions |
| Tracking issue | [#38](https://github.com/TheZen46/EconomyApp/issues/38) |
| Locations | `.github/workflows/ci.yml:26-32`<br>`.github/workflows/release.yml:13-38`<br>`android/app/build.gradle.kts:66-95`<br>`test/core/sync/live_supabase_seeder_test.dart:12-60` |

**Root cause analysis.** ci.yml sets continue-on-error: true on flutter analyze and runs `flutter test || echo "No tests defined yet"`. release.yml uses actions/upload-artifact@v3 and actions/setup-java@v3. build.gradle.kts selects the debug signing configuration for the release build type when no keystore is configured. The default test suite includes a test that requires live Supabase credentials.

Quality gates were relaxed to obtain green builds.

**Observed or potential failure mode.** Regressions, including the defects in this report, merge with a passing status. GitHub has retired v3 of the artifact actions, so the release workflow fails at the upload step. When an APK is built without signing secrets it is signed with the debug key and cannot be upgraded in place by a correctly signed build.

**Mitigation strategy.**

1. Remove continue-on-error and the `|| echo` fallback.
2. Tag network-dependent tests and exclude them by default.
3. Upgrade to actions/upload-artifact@v4 and actions/setup-java@v4.
4. Fail release builds when signing properties are absent.
5. Add jobs for build_runner drift, native compilation and native tests.

#### TAIDY-M17

**Money.roundIntegerDivision mis-rounds negative values, and awayFromZero and allocate() violate their documented contracts**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Financial Core / Money |
| Tracking issue | [#39](https://github.com/TheZen46/EconomyApp/issues/39) |
| Locations | `lib/core/financial/money.dart:133-201`<br>`lib/core/financial/currency_ratio.dart:56-82` |

**Root cause analysis.** roundIntegerDivision computes `q = numerator ~/ denominator` (truncation) and `rem = (numerator % denominator).abs()`. allocate() distributes the remainder with `for (i = 0; i < remainder; i++)`. awayFromZero returns q plus or minus one whenever rem > 0.

Dart's `%` operator returns the Euclidean (non-negative) modulus, not the remainder of truncating division; for negative numerators rem equals |denominator| minus the true remainder. Example: -13 / 10 gives q = -1 and rem = 7, and the function returns -2 instead of -1; Money.fromDecimal(-0.013) yields -2 cents. awayFromZero rounds any non-zero remainder away from zero (a ceiling-away rule) although it is documented as round-half-away. allocate() never distributes a negative remainder.

**Observed or potential failure mode.** Credit notes, refunds and negative adjustments are off by one minor unit after multiply, divide, currency conversion or construction from decimals; allocations of negative totals do not sum to the total; callers selecting awayFromZero over-round. These defects are latent in the current UI (TAIDY-A06) but affect the tax engine and any future consumer.

**Mitigation strategy.**

1. Use numerator.remainder(denominator) for the truncated remainder, or compute floor division explicitly.
2. Implement round-half-away-from-zero as documented.
3. Distribute negative remainders in allocate().
4. Extend test/financial/fuzz_financial_engine_test.dart with negative and boundary inputs checked against a BigInt reference implementation.

#### TAIDY-M18

**Tax calculations are inconsistent across modules and treat VAT-inclusive receipt prices as net amounts**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Financial Core / Tax |
| Tracking issue | [#40](https://github.com/TheZen46/EconomyApp/issues/40) |
| Locations | `lib/core/services/tax_compliance_service.dart:28-75`<br>`lib/core/services/tax_compliance_service.dart:86-143`<br>`lib/core/financial/tax_engine.dart:179-201`<br>`lib/core/financial/tax_engine.dart:216-259`<br>`lib/features/receipt_scanning/data/datasources/tax_report_service.dart:89-112`<br>`lib/features/receipt_scanning/data/datasources/tax_report_service.dart:116-209` |

**Root cause analysis.** TaxComplianceService.exportFatturaPaXml maps receipt item unitPrice directly to the net unit price and adds VAT; TaxReportService treats item totals as gross and extracts VAT. TaxEngine.inferTaxRateBps and TaxReportService.inferVatRateFromCategory use different keyword tables (for example "dairy" maps to 10% in one and to the 22% default in the other). TaxReportService labels a report with the first receipt's currency and sums amounts across currencies. TaxEngine's invariant compares totals derived from the same sums and cannot fail. The FatturaPA exporter embeds placeholder identifiers (VAT 01234567890, Via Roma 1, buyer address in Rome).

Duplicate domain logic without a shared tax model; consumer receipts are VAT-inclusive whereas invoice line items are typically net, and the code does not record which basis applies.

**Observed or potential failure mode.** The same receipt yields different VAT amounts in different outputs; exported FatturaPA totals exceed the receipt total by the VAT amount; multi-currency reports are numerically meaningless; generated XML is not a valid submission for any real party despite being described as legally compliant.

**Mitigation strategy.**

1. Introduce a single TaxRateResolver and a price-basis attribute (gross or net) on receipts and items.
2. For receipts, compute net = gross / (1 + rate) with Money and banker's rounding.
3. Group reports by currency, or convert explicitly with recorded rates.
4. Replace the tautological invariant with reconciliation against the document's stated total.
5. Require real party identifiers as parameters without defaults and validate output against the official XSD in tests.

#### TAIDY-M19

**CRDT engine contains convergence defects (positional item identity, derived totals, HLC regression) and is not integrated**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | CRDT Engine |
| Tracking issue | [#41](https://github.com/TheZen46/EconomyApp/issues/41) |
| Locations | `lib/core/crdt/receipt_crdt.dart:123-144`<br>`lib/core/crdt/receipt_crdt.dart:194-212`<br>`lib/core/crdt/crdt_sync_engine.dart:63-155`<br>`lib/core/crdt/crdt_sync_engine.dart:238-256`<br>`lib/core/crdt/crdt_sync_engine.dart:275-279` |

**Root cause analysis.** Line item identifiers are `${receipt.id}_item_$index`; updateLineItem recomputes totalAmountCents locally and stores it as an LWW register; mergeDeltaPayload advances the local HLC with Hlc(generatedAtMillis, 0, sender) rather than the maximum HLC carried in the payload; toModel sets deletedAt to DateTime.now(); pruneTombstones removes tombstones by wall-clock age; the store is held in memory only. No production code instantiates CrdtSyncEngine.

Items have no stable identity, derived values are stored as independent registers, and the clock update uses sender wall time instead of observed logical time.

**Observed or potential failure mode.** Removing an item from the middle of a receipt through recordReceipt shifts indices and leaves the last index alive, so a deleted item reappears and another item's fields change. Concurrent edits to different items produce a merged item set whose sum differs from the merged total. When a remote register carries an HLC ahead of generatedAtMillis, later local edits receive smaller HLCs and lose every merge. A replica that has not observed a pruned tombstone resurrects the receipt. The project documentation presents this engine as the synchronization mechanism.

**Mitigation strategy.**

1. Assign UUIDs to line items at creation and persist them.
2. Derive totals from the merged item set at materialization.
3. Advance the HLC with the maximum register HLC observed in the payload.
4. Derive deletedAt from the tombstone HLC and prune only after causal stability.
5. Persist the HLC and the store, then integrate the engine or remove it (TAIDY-A01).

#### TAIDY-M20

**Receipt deletion does not erase non-JPEG images from storage and mixes hard and soft deletes**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Privacy / Data Deletion |
| Tracking issue | [#42](https://github.com/TheZen46/EconomyApp/issues/42) |
| Locations | `lib/features/receipt_scanning/data/datasources/supabase_data_source.dart:225-268`<br>`lib/features/receipt_scanning/data/repositories/receipt_repository_impl.dart:139-200` |

**Root cause analysis.** deleteData derives the storage object path with a '.jpg' extension when imagePaths is not supplied, and both call sites omit imagePaths. clearAllData(includeCloud: true) hard-deletes rows with deleteReceipts, whereas the outbox and other devices rely on soft deletes (deleted_at).

The storage key depends on the original file extension at upload time but is not recorded for deletion; deletion semantics differ between code paths.

**Observed or potential failure mode.** Images uploaded as .png, .jpeg or .heic remain in the bucket (public, see TAIDY-C01) after the user deletes the receipt, which defeats erasure requests. Hard-deleted rows are never observed by other devices, which keep the receipts and can upload them again through their own outbox.

**Mitigation strategy.**

1. Persist the exact storage object path on the receipt (or list the user's prefix by receipt identifier) and delete by that path.
2. Use soft deletes consistently and purge server-side after all devices have acknowledged the tombstone.
3. Add tests covering each supported extension.

#### TAIDY-M21

**Invoice numbers are unique only per device, and automatic overdue transitions are not synchronized**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | Invoices / Numbering |
| Tracking issue | [#43](https://github.com/TheZen46/EconomyApp/issues/43) |
| Locations | `lib/features/invoices/data/providers/invoices_provider.dart:29-44`<br>`lib/features/invoices/data/providers/invoices_provider.dart:51-117` |

**Root cause analysis.** generateNextInvoiceNumber derives the next sequence from local Hive contents and a local settings counter. _load marks sent invoices as overdue by writing to Hive without updating updatedAt or version and without enqueueing an outbox mutation.

Sequential numbering requires a single authority, and the overdue transition bypasses the mutation pipeline.

**Observed or potential failure mode.** Two devices working offline, or a reinstall that has not synchronized yet, issue the same INV-YYYYMM-NNNN number, which conflicts with progressive-numbering requirements for invoices in jurisdictions such as Italy. The overdue status remains local, is reverted by the next pull and is then re-applied, producing churn.

**Mitigation strategy.**

1. Allocate invoice numbers from a server-side sequence (RPC with row locking) or partition the sequence by device.
2. Treat overdue as a derived property computed at read time, or route the transition through the outbox with updatedAt and version updates.

#### TAIDY-M22

**Training records contain fabricated tax data, placeholder identifiers and constant correction flags**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | ML Pipeline / Dataset Contribution |
| Tracking issue | [#44](https://github.com/TheZen46/EconomyApp/issues/44) |
| Locations | `lib/core/services/vlm/dataset_contribution_service.dart:56-89`<br>`lib/features/receipt_scanning/data/datasources/supabase_data_source.dart:117-144`<br>`native/grammars/receipt.gbnf:1-47`<br>`native/src/receipt_engine.cpp:497-507` |

**Root cause analysis.** stageVerifiedReceipt writes vat_number 'IT12345678901' and a tax_breakdown of 22% with taxable 82% and tax 18% of the total for every receipt, using the keys rate_percent and taxable_amount, whereas the engine output uses rate and tax_amount. uploadTrainingData marks every label with is_user_corrected: true and original_ai_prediction_was_wrong: true.

Placeholder values are substituted for missing data instead of being omitted, and the training schema is defined independently of the inference schema.

**Observed or potential failure mode.** Models fine-tuned on these records learn to emit a constant VAT number and a fixed 22% tax split; the correction flags carry no signal; supervised targets do not match what the constrained decoder can produce.

**Mitigation strategy.**

1. Omit unknown fields or set them to null; derive the tax breakdown from receipt data when present.
2. Set correction flags from an actual comparison of AI output and saved values.
3. Define the receipt schema once and generate both the GBNF grammar and the training export from it.

#### TAIDY-M23

**LLMService.generate never completes when the model fails to load and leaks its receive port on cancellation**

| Attribute | Value |
|---|---|
| Severity | Medium |
| Component | AI / LLMService |
| Tracking issue | [#45](https://github.com/TheZen46/EconomyApp/issues/45) |
| Locations | `lib/core/services/llm_service_mobile.dart:196-241` |

**Root cause analysis.** _streamLlamaInIsolate constructs Llama(request.modelPath) before the try block, and the completion signal (null) is sent from finally. generate() closes the ReceivePort only after the await-for loop finishes normally.

The constructor is outside the protected region, and the consumer loop has no try/finally.

**Observed or potential failure mode.** A corrupt or missing model terminates the isolate without sending the completion signal and the consumer waits indefinitely. Cancelling the stream leaves the port open and the isolate running.

**Mitigation strategy.**

1. Move model construction inside the try block.
2. Pass onExit and onError ports to Isolate.spawn and translate termination into stream completion or error.
3. Close the port in a finally block of the generator.

### 4.4 Low

#### TAIDY-L01

**TextEditingController instances are not disposed in several pages and dialogs**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Presentation / Resource Management |
| Tracking issue | [#46](https://github.com/TheZen46/EconomyApp/issues/46) |
| Locations | `lib/features/settings/presentation/pages/integrations_page.dart:16-19`<br>`lib/features/receipt_scanning/presentation/pages/review_page.dart:31-75`<br>`lib/features/settings/presentation/pages/settings_page.dart:916`<br>`lib/features/settings/presentation/pages/taxonomy_settings_page.dart:114` |

**Root cause analysis.** _IntegrationsPageState and _ReviewPageState create controllers (and ReviewPage adds listeners) without overriding dispose(); dialog builders in SettingsPage and TaxonomySettingsPage allocate controllers that are never released.

Missing lifecycle teardown.

**Observed or potential failure mode.** Controllers and their listeners leak per page visit or dialog; ReviewPage listeners can call setState after the state object is unmounted.

**Mitigation strategy.**

1. Override dispose() and dispose every controller.
2. For dialogs, create controllers inside a StatefulWidget used as the dialog body, or dispose them after showDialog completes.

#### TAIDY-L02

**CSV exports are vulnerable to spreadsheet formula injection**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Export / CSV |
| Tracking issue | [#47](https://github.com/TheZen46/EconomyApp/issues/47) |
| Locations | `lib/core/services/export_service.dart:18-96`<br>`lib/core/services/export_service.dart:150-200`<br>`lib/features/receipt_scanning/data/datasources/tax_report_service.dart:224-260` |

**Root cause analysis.** Merchant names, item descriptions and client names, which originate from OCR, AI output, CSV imports or user input, are written to CSV cells without neutralisation.

No escaping of cells that begin with =, +, -, @, tab or carriage return.

**Observed or potential failure mode.** A receipt whose merchant text begins with "=" (for example from a crafted CSV import or OCR of a crafted receipt) is evaluated as a formula when the export is opened in a spreadsheet application, which can exfiltrate data through external references.

**Mitigation strategy.**

1. Prefix such cells with a single quote (or a leading space) per OWASP guidance in a shared CSV cell sanitizer used by every exporter.
2. Add unit tests for each leading character.

#### TAIDY-L03

**JSON repair heuristics corrupt string content containing "//" or the words True, False and None**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Core Utilities / JsonParserUtils |
| Tracking issue | [#48](https://github.com/TheZen46/EconomyApp/issues/48) |
| Locations | `lib/core/utils/json_parser_utils.dart:124-152` |

**Root cause analysis.** repairJson removes text matching `//.*$` and replaces \bNone\b, \bTrue\b and \bFalse\b across the entire payload, including inside string literals.

Regular-expression substitutions are not aware of string boundaries, unlike the subsequent character scanners in the same file.

**Observed or potential failure mode.** On the repair path, a URL such as "https://example.com" is truncated to "https:", producing either a parse failure or a corrupted value; merchant names such as "True Value" become "true Value".

**Mitigation strategy.**

1. Perform comment stripping and literal replacement in the same string-aware scanner used by _sanitizeStringLiterals.
2. Add tests with URLs and capitalised words inside strings.

#### TAIDY-L04

**Global error handler suppresses every uncaught asynchronous error and the telemetry log grows without bound**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Observability / TelemetryService |
| Tracking issue | [#49](https://github.com/TheZen46/EconomyApp/issues/49) |
| Locations | `lib/core/services/telemetry_service.dart:136-160`<br>`lib/core/services/telemetry_service.dart:244-279` |

**Root cause analysis.** PlatformDispatcher.instance.onError records the error and returns true for every error, marking it fatal while allowing execution to continue. Events are appended to telemetry_events.jsonl indefinitely. A Sentry DSN parameter exists but nothing transmits events.

"Handled" is reported for errors that the application did not handle; no retention policy.

**Observed or potential failure mode.** The application continues after errors that leave state inconsistent, which hides defects such as those in TAIDY-M04 and TAIDY-M05 from users and developers; the log file grows for the lifetime of the installation.

**Mitigation strategy.**

1. Return false (or rethrow in debug builds) for errors that are not explicitly recoverable, and present a recovery screen for fatal ones.
2. Rotate the log by size and age.
3. Either implement remote reporting with consent or remove the unused DSN parameter.

#### TAIDY-L05

**User-facing confidence, benchmark and verification indicators are synthetic**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Presentation / Diagnostics |
| Tracking issue | [#50](https://github.com/TheZen46/EconomyApp/issues/50) |
| Locations | `lib/features/receipt_scanning/presentation/pages/scan_page.dart:202-224`<br>`lib/core/services/vlm/vlm_engine_service.dart:274-303`<br>`lib/features/sync/data/datasources/sync_engine.dart:309-316`<br>`lib/core/services/vlm/vlm_engine_service.dart:158-170` |

**Root cause analysis.** The scan page displays a confidence value that starts at 92% and adds fixed increments when fields are non-empty; benchmarkInference reports tokens per second from a clamped formula unrelated to inference and always returns status PASSED; SyncEngine reports "Verifying bit-for-bit directory integrity" during a fixed 300 ms delay; inference telemetry always reports model Qwen2-VL-2B-Instruct regardless of the loaded model.

Placeholder values are presented as measurements.

**Observed or potential failure mode.** Users and developers make decisions (accepting AI output, choosing a model, trusting sync parity) on fabricated indicators.

**Mitigation strategy.**

1. Display model-reported confidence or none at all.
2. Measure actual inference throughput or remove the benchmark.
3. Remove the simulated verification stage or implement it.
4. Record the identifier of the model actually loaded.

#### TAIDY-L06

**UpdateState.copyWith cannot clear message or error, leaving stale notifications**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | AI / ModelUpdateService |
| Tracking issue | [#51](https://github.com/TheZen46/EconomyApp/issues/51) |
| Locations | `lib/features/receipt_scanning/presentation/providers/model_update_provider.dart:24-38`<br>`lib/features/receipt_scanning/presentation/providers/model_update_provider.dart:50-80`<br>`lib/main.dart:401-422` |

**Root cause analysis.** copyWith uses `message ?? this.message` and `error ?? this.error`, yet callers pass message: null to clear the message.

Nullable fields cannot be reset through a null-coalescing copyWith.

**Observed or potential failure mode.** "Checking for AI updates..." and previous errors persist in state after the check completes; UpgradeListenerWrapper shows a snackbar on each launch.

**Mitigation strategy.**

1. Use a sentinel or explicit clear flags in copyWith, or construct a fresh UpdateState when clearing.

#### TAIDY-L07

**Repository tracks node_modules, stray artifacts and an orphaned duplicate native engine**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Repository Hygiene |
| Tracking issue | [#52](https://github.com/TheZen46/EconomyApp/issues/52) |
| Locations | `node_modules/`<br>`package.json:1-7`<br>`git_error2.txt:1-35`<br>`flutter_01.png`<br>`native/receipt_vlm/`<br>`native/grammars/receipt.gbnf`<br>`native/receipt_vlm/grammar/receipt.gbnf` |

**Root cause analysis.** 2,227 files under node_modules/ (puppeteer and dependencies) are committed; git_error2.txt is a captured push-protection log; flutter_01.png is a zero-byte file; native/receipt_vlm/ is a second engine implementation and grammar not referenced by any build file.

Missing ignore rules and no ownership of experimental trees.

**Observed or potential failure mode.** Clone size and review noise increase; contributors may edit the orphaned engine or grammar in the belief that it is used; tooling that scans the repository reports third-party code as project code.

**Mitigation strategy.**

1. Remove node_modules from the index and add it to .gitignore (keep package.json and the lockfile if the dependency is needed for tooling).
2. Delete stray artifacts.
3. Remove native/receipt_vlm or move it to an archive branch, and keep a single grammar source.

#### TAIDY-L08

**A dead-lettered upload blocks re-scheduling of the same receipt, and each upload scans every receipt**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Sync / SyncService |
| Tracking issue | [#53](https://github.com/TheZen46/EconomyApp/issues/53) |
| Locations | `lib/features/receipt_scanning/data/datasources/sync_service.dart:54-72`<br>`lib/features/receipt_scanning/data/datasources/sync_service.dart:204-228` |

**Root cause analysis.** scheduleUpload returns early when any queue item has the same receiptId, including items in the permanentlyFailed state. _uploadItem loads all receipts and searches linearly for each queued item.

The duplicate check does not consider item state; no keyed lookup.

**Observed or potential failure mode.** After five failures, later edits to the receipt are never uploaded by this path until a manual retry, which has no UI entry point outside the failed-items list; queue processing is quadratic in the number of receipts.

**Mitigation strategy.**

1. Replace a dead-lettered entry when the receipt is saved again.
2. Use receiptBox.get(id) for keyed access.

#### TAIDY-L09

**PII scrubber over-redacts ordinary text and does not cover personal names**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Privacy / PiiScrubberService |
| Tracking issue | [#54](https://github.com/TheZen46/EconomyApp/issues/54) |
| Locations | `lib/core/privacy/pii_scrubber_service.dart:28-32`<br>`lib/core/privacy/pii_scrubber_service.dart:64-66`<br>`lib/features/receipt_scanning/data/datasources/mock_ai_service.dart:74-94` |

**Root cause analysis.** The address pattern matches "Via", "Dr." or "St." anywhere and redacts the remainder of the line; there is no rule for personal names (for example "Cashier: Mario Rossi"). Separately, the OCR heuristic date parser assumes day-first order and does not validate overflow.

Keyword patterns without context, and no named-entity handling.

**Observed or potential failure mode.** Item descriptions such as "Dr. Pepper" or "sent via courier" lose their content in the training corpus; names on receipts pass through unredacted.

**Mitigation strategy.**

1. Anchor address patterns to number-plus-street structures and test with negative examples.
2. Add a names rule (gazetteer or lightweight NER) or exclude free-text fields from the corpus.
3. Validate parsed dates by round-tripping components.

### 4.5 Documentation Coverage and Accuracy (severity Low)

#### TAIDY-D01

**Public API documentation coverage is 36 percent, with several modules at zero**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Documentation / API Coverage |
| Tracking issue | [#55](https://github.com/TheZen46/EconomyApp/issues/55) |
| Locations | `lib/core/error/failures.dart`<br>`lib/core/routes/app_router.dart`<br>`lib/core/theme/theme_notifier.dart`<br>`lib/core/sync/sync_providers.dart`<br>`lib/features/settings/presentation/providers/llm_provider.dart`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart`<br>`lib/features/invoices/data/providers/invoices_provider.dart`<br>`lib/main.dart` |

**Root cause analysis.** A static count of public top-level declarations (classes, enums, typedefs, top-level providers and functions) found 105 of 295 preceded by a /// documentation comment. Modules at 0 percent: lib/core/error, lib/core/routes, lib/core/theme, lib/features/settings and lib/main.dart. lib/features/receipt_scanning is at 24 percent, lib/features/invoices at 14 percent and lib/features/evault at 20 percent. The per-module table is included in audit/findings_report.md.

No documentation lint is enabled (public_member_api_docs is not in analysis_options.yaml).

**Observed or potential failure mode.** Provider override contracts (for example which providers must be overridden in main), failure semantics and persistence keys are discoverable only by reading implementations, which increases the cost of changes and contributed to the contract drift recorded in this report.

**Mitigation strategy.**

1. Document every provider with its lifetime, override requirement and dependencies; document every Failure subtype with its producer.
2. Enable public_member_api_docs for lib/core and data layers, and raise coverage module by module.

#### TAIDY-D02

**Existing documentation diverges from the implementation and from repository style policy**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Documentation / Accuracy |
| Tracking issue | [#56](https://github.com/TheZen46/EconomyApp/issues/56) |
| Locations | `README.md:18-21`<br>`README.md:91-95`<br>`docs/architecture.md:56-155`<br>`docs/architecture.md:247-316`<br>`docs/api_reference.md:1-178`<br>`docs/troubleshooting.md:1-136`<br>`docs/release_0.1.3_guide.md:16-60` |

**Root cause analysis.** docs/architecture.md presents code excerpts that differ from the source (AuthNotifier is shown taking a SupabaseClient; the backup routine is shown writing next to the box file). README and docs describe bit-for-bit verification, delta hashing, network isolation, CRDT-based synchronization, zero-copy inference and legally compliant fiscal export, none of which is implemented as described (see TAIDY-M08, TAIDY-H17, TAIDY-A01, TAIDY-A05, TAIDY-M18). Headings in docs/troubleshooting.md and docs/api_reference.md contain emoji, which AGENTS.md prohibits.

Documentation was written from intended design rather than generated from or checked against code.

**Observed or potential failure mode.** Contributors and users rely on guarantees that do not exist, including privacy guarantees.

**Mitigation strategy.**

1. Rewrite architecture, data flow and troubleshooting documentation from the current code (addressed by the documentation added with this audit).
2. Remove or qualify unimplemented claims in README.md, docs/api_reference.md and docs/release_0.1.3_guide.md.
3. Add a documentation review item to the pull request checklist.

#### TAIDY-D03

**Operational contracts are undocumented (Hive type registry, outbox state machine, remote column mapping, conflict policy, data inventory)**

| Attribute | Value |
|---|---|
| Severity | Low |
| Component | Documentation / Operational Contracts |
| Tracking issue | [#57](https://github.com/TheZen46/EconomyApp/issues/57) |
| Locations | `lib/main.dart:69-81`<br>`lib/core/sync/models/sync_outbox_item.dart:1-82`<br>`supabase/migrations/20260828_master_sync_schema.sql`<br>`lib/core/sync/sync_manager.dart:284-291` |

**Root cause analysis.** Hive type identifiers, box names and settings keys, the outbox status lifecycle, the mapping between Dart fields and SQL columns, the conflict resolution policy and the inventory of stored personal data are not written down anywhere.

Contracts exist only implicitly in code.

**Observed or potential failure mode.** Defects such as TAIDY-H06 (typeId collision), TAIDY-C03 (column mismatch) and TAIDY-M01 (key ownership conflict) arise from undocumented contracts.

**Mitigation strategy.**

1. Maintain docs/contracts/ with a typeId and box registry, settings key ownership, outbox state diagram, table-to-DTO mapping and a personal-data inventory, and reference them from code comments.
2. Back each document with a test that fails when the contract changes without the document.

### 4.6 Architectural

#### TAIDY-A01

**Three overlapping synchronization subsystems operate on the same stores without a shared contract, and the CRDT engine is not wired in**

| Attribute | Value |
|---|---|
| Severity | Architectural |
| Component | Sync / Architecture |
| Tracking issue | [#58](https://github.com/TheZen46/EconomyApp/issues/58) |
| Locations | `lib/core/sync/sync_manager.dart:1-311`<br>`lib/features/receipt_scanning/data/datasources/sync_service.dart:1-233`<br>`lib/features/sync/data/datasources/sync_engine.dart:1-498`<br>`lib/core/crdt/crdt_sync_engine.dart:1-280`<br>`lib/features/receipt_scanning/data/repositories/receipt_repository_impl.dart:59-126` |

**Root cause analysis.** SyncManager (outbox push plus delta pull with version-based LWW), SyncService (sync_queue upload of images, labels and a receipts row with a different column set) and SyncEngine (full replication on login with its own row parsers) each write to the same Hive boxes and remote tables. Each has its own lock, connectivity subscription and retry policy. saveReceipt feeds two of them for every receipt. CrdtSyncEngine is documented as the mechanism but is not referenced by application code.

Incremental feature additions without consolidation; no single owner of the replication protocol.

**Observed or potential failure mode.** Concurrent writers interleave updates to the same box without mutual exclusion; the same receipt is written to public.receipts by two code paths with different shapes; fixes must be applied in three places (see TAIDY-H03, TAIDY-H04, TAIDY-H05, TAIDY-C03); behaviour depends on which engine ran last.

**Mitigation strategy.**

1. Define one replication protocol (push via outbox, pull via server cursor, explicit conflict policy) in a single SyncCoordinator with one lock.
2. Reduce SyncService to an attachment-upload worker that the coordinator invokes.
3. Reduce SyncEngine to a progress presenter over the coordinator's first full pull.
4. Decide whether CRDT merging is required; if so integrate it at the entity level, otherwise remove it and correct the documentation.

#### TAIDY-A02

**Core modules depend on feature modules, producing cyclic dependencies**

| Attribute | Value |
|---|---|
| Severity | Architectural |
| Component | Layering / Dependency Graph |
| Tracking issue | [#59](https://github.com/TheZen46/EconomyApp/issues/59) |
| Locations | `lib/core/sync/sync_providers.dart:7-14`<br>`lib/core/sync/sync_manager.dart:10-13`<br>`lib/core/services/biometric_service.dart:5`<br>`lib/core/theme/theme_notifier.dart:4`<br>`lib/core/crdt/receipt_crdt.dart:3-4`<br>`lib/core/privacy/pii_scrubber_service.dart:1`<br>`lib/core/services/export_service.dart:6-7`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:39-47` |

**Root cause analysis.** core/sync imports feature models and providers; core/services/biometric_service.dart and core/theme/theme_notifier.dart import the receipt feature's provider file to obtain settingsBoxProvider; infrastructure providers (hiveBoxProvider, settingsBoxProvider, syncBoxProvider) are declared in the receipt feature, which in turn imports core/sync.

Shared infrastructure was placed in the first feature that needed it.

**Observed or potential failure mode.** Features cannot be compiled, tested or removed independently; changes in the receipt feature trigger rebuilds and test failures across core; the import cycle obscures initialization order.

**Mitigation strategy.**

1. Move infrastructure providers (Hive boxes, Supabase client, secure storage) into lib/core/di or a dedicated bootstrap module.
2. Define entity-agnostic interfaces in core (for example a SyncableEntity contract) implemented by features.
3. Enforce the direction with an import-lint rule (for example dependency_validator or custom_lint).

#### TAIDY-A03

**No single serialization contract exists between Dart models and the remote schema; at least seven hand-written mappers diverge**

| Attribute | Value |
|---|---|
| Severity | Architectural |
| Component | Data Contracts / Serialization |
| Tracking issue | [#60](https://github.com/TheZen46/EconomyApp/issues/60) |
| Locations | `lib/features/receipt_scanning/data/models/receipt_model.dart:75-142`<br>`lib/features/sync/data/datasources/sync_engine.dart:397-491`<br>`lib/features/receipt_scanning/data/datasources/supabase_data_source.dart:117-176`<br>`lib/core/services/vlm/vlm_engine_service.dart:195-253`<br>`lib/core/services/llm_service_mobile.dart:146-173`<br>`lib/features/receipt_scanning/data/datasources/gemini_ai_service.dart:105-109`<br>`lib/core/services/export_service.dart:106-127`<br>`supabase/migrations/20260828_master_sync_schema.sql:45-307` |

**Root cause analysis.** Receipt rows and AI outputs are converted by independent functions that disagree on field names (date vs scanned_date, color vs color_hex), on defaults (currency USD vs EUR, necessity essential vs unknown), and on which fields exist (items, image_url, version).

Models are hand-written with ad-hoc fromJson/toJson; no generated or validated schema binding.

**Observed or potential failure mode.** Every schema change requires coordinated edits in several files; drift has already produced TAIDY-C03, TAIDY-H05 and TAIDY-H15.

**Mitigation strategy.**

1. Define DTOs per remote table generated with json_serializable (field renames via @JsonKey) and a single mapping layer between DTOs and domain entities.
2. Define one AI output schema shared by Gemini, LLM and VLM backends, with one parser.
3. Add a schema contract test in CI that compares DTO fields with the migration.

#### TAIDY-A04

**Static singletons and exception-driven provider wiring impede testing and substitution**

| Attribute | Value |
|---|---|
| Severity | Architectural |
| Component | Dependency Injection |
| Tracking issue | [#61](https://github.com/TheZen46/EconomyApp/issues/61) |
| Locations | `lib/core/services/secure_storage_service.dart:9-111`<br>`lib/core/services/secure_storage_service.dart:125-127`<br>`lib/core/services/telemetry_service.dart:103-112`<br>`lib/core/services/google_drive_service.dart:254`<br>`lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:39-47`<br>`lib/core/sync/sync_providers.dart:25-66` |

**Root cause analysis.** SecureStorageService exposes only static members while secureStorageProvider returns an instance with no usable API; TelemetryService.instance, the global googleDriveService and Supabase.instance are referenced directly from services. Providers that must be overridden throw UnimplementedError, and consumers wrap ref.watch in try/catch to detect absence.

Mixed service-locator and provider patterns; absence is signalled by exceptions instead of types.

**Observed or potential failure mode.** Services cannot be replaced with fakes without platform channels; missing overrides are silently tolerated (for example syncManagerProvider returning null), which hides configuration errors.

**Mitigation strategy.**

1. Convert static services to instance classes injected through providers.
2. Model optional dependencies as nullable providers or AsyncValue rather than catching exceptions.
3. Add a ProviderContainer test that asserts all required overrides are present.

#### TAIDY-A05

**On-device VLM pipeline is not integrated end to end**

| Attribute | Value |
|---|---|
| Severity | Architectural |
| Component | Native Engine / Integration |
| Tracking issue | [#62](https://github.com/TheZen46/EconomyApp/issues/62) |
| Locations | `native/src/receipt_engine.cpp:276-282`<br>`native/src/receipt_engine.cpp:783-793`<br>`native/CMakeLists.txt:1-182`<br>`linux/CMakeLists.txt`<br>`windows/CMakeLists.txt`<br>`ios/receipt_engine.podspec:1-25`<br>`lib/core/services/vlm/vlm_ffi_bindings_ffi.dart:190-218`<br>`lib/features/settings/presentation/pages/model_manager_page.dart:80-100` |

**Root cause analysis.** execute_grammar_constrained_sampling receives the preprocessed image but never uses it; the normalized CLIP tensor computed in receipt_engine_process_image is discarded; no CLIP or mtmd API is called. The desktop runners do not build or bundle libreceipt_engine; the iOS podspec is not referenced by any Podfile (none is tracked). VLM readiness is set only from the model manager page, not at startup. Documentation describes zero-copy GPU buffers and a paged KV cache whose structures are allocated but not connected to inference.

Native scaffolding was written ahead of the inference integration, and the stubs (TAIDY-C04) concealed the gap.

**Observed or potential failure mode.** Even with a real llama.cpp build, the model would generate text without seeing the receipt, so every output would be hallucinated; desktop and iOS builds cannot load the library; after restart the VLM is never selected until the user opens the model manager.

**Mitigation strategy.**

1. Integrate the multimodal path (llama.cpp mtmd/clip) with image embeddings fed before text decoding, and validate on a reference image set.
2. Add CMake integration for Linux, Windows and macOS runners and a podspec reference for iOS, or restrict the feature to Android until available.
3. Initialize VLM readiness at startup from verified model files.
4. Align documentation with implemented capabilities.

#### TAIDY-A06

**Financial, tax, reconciliation and CRDT modules are unreachable from the application**

| Attribute | Value |
|---|---|
| Severity | Architectural |
| Component | Codebase Structure |
| Tracking issue | [#63](https://github.com/TheZen46/EconomyApp/issues/63) |
| Locations | `lib/core/services/tax_compliance_service.dart:1-446`<br>`lib/core/financial/tax_engine.dart:1-277`<br>`lib/core/financial/money.dart:1-288`<br>`lib/core/financial/currency_ratio.dart:1-149`<br>`lib/features/receipt_scanning/data/datasources/bank_reconciliation_service.dart:1-341`<br>`lib/features/receipt_scanning/data/datasources/tax_report_service.dart:1-346`<br>`lib/core/crdt/`<br>`lib/features/boxes/data/providers/boxes_provider.dart:122-131` |

**Root cause analysis.** No file under lib/ outside these modules references TaxComplianceService, TaxEngine, Money, CurrencyRatio, BankReconciliationService, TaxReportService or CrdtSyncEngine. BoxesNotifier.addSpent has no caller, so BoxModel.spent never reflects receipts. The CHANGELOG and release guide describe these capabilities as shipped.

Modules were developed and unit-tested in isolation without integration into user flows.

**Observed or potential failure mode.** Maintenance cost without user value; documentation overstates functionality; defects in these modules (TAIDY-M17, TAIDY-M18, TAIDY-M19) remain unnoticed because no flow exercises them.

**Mitigation strategy.**

1. For each module, decide to integrate (with a tracked issue and acceptance criteria) or remove.
2. Mark experimental modules explicitly and exclude them from release claims.

#### TAIDY-A07

**Monetary amounts are persisted and computed as double while the fixed-point Money type is unused**

| Attribute | Value |
|---|---|
| Severity | Architectural |
| Component | Financial Core / Monetary Representation |
| Tracking issue | [#64](https://github.com/TheZen46/EconomyApp/issues/64) |
| Locations | `lib/features/receipt_scanning/data/models/receipt_model.dart:17-18`<br>`lib/features/receipt_scanning/data/models/receipt_model.dart:222-229`<br>`lib/features/invoices/data/models/invoice_model.dart:29-30`<br>`lib/features/boxes/data/models/box_model.dart:1-60`<br>`lib/core/financial/money.dart:16-38` |

**Root cause analysis.** ReceiptModel.totalAmount, item prices, invoice amounts and box budgets are double values in Hive, in JSON and in UI aggregation. Money (integer minor units with banker's rounding) is used only by the unreachable tax export module.

The fixed-point type was introduced after the persistence model and was never adopted.

**Observed or potential failure mode.** Sums over many receipts accumulate binary floating-point error; equality checks on totals are unreliable; currency minor-unit differences (for example JPY with zero decimals) are not modelled.

**Mitigation strategy.**

1. Store amounts as integer minor units with an ISO 4217 currency code in Hive (new fields with a migration) and in the remote schema (NUMERIC is already exact).
2. Convert at the boundary and perform arithmetic with Money.

#### TAIDY-A08

**AI backend selection is an implicit reactive cascade without capability negotiation, consent or provenance**

| Attribute | Value |
|---|---|
| Severity | Architectural |
| Component | AI / Backend Selection |
| Tracking issue | [#65](https://github.com/TheZen46/EconomyApp/issues/65) |
| Locations | `lib/features/receipt_scanning/presentation/providers/receipt_provider.dart:85-115`<br>`lib/main.dart:330-345`<br>`lib/features/settings/presentation/providers/llm_provider.dart:1-29`<br>`lib/features/settings/presentation/pages/model_manager_page.dart:80-150` |

**Root cause analysis.** aiServiceProvider chooses VLM, LLM, Gemini or the fallback from four independent flags; readiness flags are mutable StateProviders set from different pages; cloud processing is enabled by a settings flag without recording consent; results carry no indication of which backend produced them.

Backend availability, user preference and privacy policy are encoded as loosely coupled booleans.

**Observed or potential failure mode.** The active backend changes during a session without notice (and recreates the repository, see TAIDY-M04); images may be sent to the cloud tier while the user believes processing is local; analytics and training data cannot distinguish backend quality.

**Mitigation strategy.**

1. Introduce an AiBackendRegistry exposing capability, readiness and privacy class (on-device or cloud) per backend.
2. Select the backend per request according to an explicit user policy with recorded consent for cloud processing.
3. Attach provenance (backend, model identifier, version, confidence) to every extraction result.

#### TAIDY-A09

**Core dependencies are unmaintained, deprecated or pinned to old exact versions**

| Attribute | Value |
|---|---|
| Severity | Architectural |
| Component | Dependencies |
| Tracking issue | [#66](https://github.com/TheZen46/EconomyApp/issues/66) |
| Locations | `pubspec.yaml:33-96` |

**Root cause analysis.** hive 2.2.3 and hive_flutter 1.1.0 have not received releases since 2022 (a community fork, hive_ce, is maintained); google_generative_ai is deprecated by its publisher; json_annotation 4.8.1, freezed_annotation 2.4.1 and freezed 2.5.2 are pinned to exact older versions.

No dependency update policy.

**Observed or potential failure mode.** Platform and SDK upgrades can break persistence with no upstream fixes; security and API changes in deprecated SDKs are not received; exact pins block transitive upgrades.

**Mitigation strategy.**

1. Plan a migration to hive_ce (binary compatible) or to an alternative such as SQLite with SQLCipher.
2. Migrate the cloud AI client to the supported SDK.
3. Use caret constraints and add automated dependency update checks (for example Dependabot for pub).

## 5. Documentation Coverage Measurement

Coverage was measured by counting public top-level declarations (classes, enums, mixins, extensions, typedefs, top-level providers and top-level functions) and checking whether the nearest preceding non-annotation line is a `///` documentation comment. Member-level documentation is outside the scope of this measurement.

| Module | Public declarations | Documented | Coverage (%) |
|---|---|---|---|
| `lib/core/constants` | 3 | 1 | 33 |
| `lib/core/crdt` | 7 | 7 | 100 |
| `lib/core/error` | 13 | 0 | 0 |
| `lib/core/financial` | 7 | 7 | 100 |
| `lib/core/privacy` | 1 | 1 | 100 |
| `lib/core/routes` | 2 | 0 | 0 |
| `lib/core/services` | 60 | 29 | 48 |
| `lib/core/sync` | 6 | 3 | 50 |
| `lib/core/theme` | 6 | 0 | 0 |
| `lib/core/utils` | 3 | 2 | 67 |
| `lib/features/auth` | 16 | 7 | 44 |
| `lib/features/boxes` | 13 | 7 | 54 |
| `lib/features/evault` | 5 | 1 | 20 |
| `lib/features/invoices` | 7 | 1 | 14 |
| `lib/features/receipt_scanning` | 106 | 25 | 24 |
| `lib/features/settings` | 24 | 0 | 0 |
| `lib/features/sync` | 14 | 14 | 100 |
| `lib/main.dart` | 2 | 0 | 0 |
| `TOTAL` | 295 | 105 | 36 |

Files with two or more public declarations and no documentation comments:

- `lib/core/constants/taxonomy_constants.dart` (2 declarations)
- `lib/core/error/failures.dart` (13 declarations)
- `lib/core/routes/app_router.dart` (2 declarations)
- `lib/core/services/biometric_service.dart` (4 declarations)
- `lib/core/sync/sync_providers.dart` (3 declarations)
- `lib/core/theme/app_theme.dart` (2 declarations)
- `lib/core/theme/theme_notifier.dart` (4 declarations)
- `lib/features/boxes/data/providers/boxes_provider.dart` (4 declarations)
- `lib/features/evault/presentation/providers/asset_provider.dart` (3 declarations)
- `lib/features/invoices/data/models/invoice_model.dart` (2 declarations)
- `lib/features/invoices/data/providers/invoices_provider.dart` (3 declarations)
- `lib/features/receipt_scanning/data/datasources/hive_receipt_data_source.dart` (2 declarations)
- `lib/features/receipt_scanning/data/datasources/supabase_data_source.dart` (2 declarations)
- `lib/features/receipt_scanning/data/models/app_config.dart` (2 declarations)
- `lib/features/receipt_scanning/data/models/dashboard_config.dart` (2 declarations)
- `lib/features/receipt_scanning/data/models/receipt_model.dart` (2 declarations)
- `lib/features/receipt_scanning/data/models/sync_item_model.dart` (2 declarations)
- `lib/features/receipt_scanning/domain/entities/receipt.dart` (3 declarations)
- `lib/features/receipt_scanning/presentation/pages/scan_page.dart` (2 declarations)
- `lib/features/receipt_scanning/presentation/providers/category_provider.dart` (2 declarations)
- `lib/features/receipt_scanning/presentation/providers/dashboard_provider.dart` (2 declarations)
- `lib/features/receipt_scanning/presentation/providers/model_update_provider.dart` (2 declarations)
- `lib/features/receipt_scanning/presentation/widgets/interactive_hover.dart` (2 declarations)
- `lib/features/receipt_scanning/presentation/widgets/receipt_item_row.dart` (2 declarations)
- `lib/features/settings/data/models/taxonomy_model.dart` (2 declarations)
- `lib/features/settings/presentation/pages/settings_page.dart` (2 declarations)
- `lib/features/settings/presentation/providers/llm_provider.dart` (12 declarations)
- `lib/features/settings/presentation/providers/taxonomy_provider.dart` (2 declarations)
- `lib/main.dart` (2 declarations)

## 6. Recommended Remediation Order

1. Containment of data exposure: TAIDY-C01, TAIDY-H01, TAIDY-H02, TAIDY-H17, TAIDY-M14, TAIDY-M20. These require schema migrations and configuration changes and should precede any further release.
2. Prevention of data loss: TAIDY-C02, TAIDY-H04, TAIDY-H05, TAIDY-H07, TAIDY-M09.
3. Disabling or completing the native inference path: TAIDY-C04, TAIDY-H08, TAIDY-H09, TAIDY-H10, TAIDY-H16, TAIDY-A05; until resolved, keep the VLM backend unreachable in release builds.
4. Removal of fabricated outputs: TAIDY-H12, TAIDY-H15, TAIDY-L05, TAIDY-M22.
5. Synchronization redesign: TAIDY-C03, TAIDY-H03, TAIDY-M02, TAIDY-M03, TAIDY-M08, TAIDY-A01, TAIDY-A03.
6. Restoration of quality gates so that the above remain fixed: TAIDY-M16, TAIDY-H06, TAIDY-D01.

## Appendix A. Reviewed Artifacts

| Area | Paths |
|---|---|
| Application bootstrap | `lib/main.dart` |
| Core services | `lib/core/**` (CRDT, financial, privacy, routes, services, sync, theme, utils) |
| Features | `lib/features/{auth,boxes,evault,invoices,receipt_scanning,settings,sync}/**` |
| Native engine | `native/src/**`, `native/receipt_vlm/**`, `native/CMakeLists.txt`, `android/app/src/main/cpp/CMakeLists.txt`, `ios/receipt_engine.podspec` |
| Backend schema | `supabase/schema.sql`, `supabase/migrations/*.sql`, `supabase/seed_dummy_data.sql` |
| Build and CI | `pubspec.yaml`, `analysis_options.yaml`, `android/app/build.gradle.kts`, `.github/workflows/*.yml` |
| Documentation | `README.md`, `PROJECT.md`, `CHANGELOG.md`, `docs/*.md` |
