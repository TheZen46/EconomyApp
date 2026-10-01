# tAIdy Data Flow

This document traces the life cycle of data in tAIdy (EconomyApp) from capture to persistence,
replication, export and deletion, as implemented at revision `c66e079`. Each pipeline is described as
an ordered sequence of steps naming the function that executes it, the data representation it
consumes and produces, and the failure behaviour of the step. Where a step deviates from its intended
behaviour, the corresponding audit finding (`audit/findings_report.md`) and tracking issue are cited.

The component structure referred to here is described in `docs/architecture.md`.

## Contents

1. [Data Representations](#1-data-representations)
2. [Session Establishment](#2-session-establishment)
3. [Receipt Capture and Extraction](#3-receipt-capture-and-extraction)
4. [Review and Local Commit](#4-review-and-local-commit)
5. [Outbound Replication: Outbox Push](#5-outbound-replication-outbox-push)
6. [Outbound Replication: Attachment and Label Upload](#6-outbound-replication-attachment-and-label-upload)
7. [Inbound Replication: Delta Pull](#7-inbound-replication-delta-pull)
8. [Inbound Replication: Initial Full Replication](#8-inbound-replication-initial-full-replication)
9. [Deletion](#9-deletion)
10. [Secondary Pipelines](#10-secondary-pipelines)
11. [AI Output Normalization](#11-ai-output-normalization)
12. [Data Inventory and Retention](#12-data-inventory-and-retention)

---

## 1. Data Representations

A receipt passes through six representations. Each transformation is a separate function, which is
why field names and defaults can diverge between paths (`TAIDY-A03`, issue #60).

```
 image file (JPEG/PNG path from image_picker)
     |  File.readAsBytes / XFile.readAsBytes
     v
 Uint8List image bytes
     |  AIService.extractReceiptData(...)  -- backend-specific JSON (Section 11)
     v
 Receipt (freezed domain entity, lib/features/receipt_scanning/domain/entities/receipt.dart)
     |  ReceiptModel.fromEntity(receipt)
     v
 ReceiptModel (Hive object, typeId 0, box receipts_v3)
     |  ReceiptModel.toJson()
     v
 Map<String, dynamic> outbox payload (SyncOutboxItem.payload, box sync_outbox)
     |  SupabaseClient.from('receipts').upsert(payload)
     v
 PostgreSQL row in public.receipts
```

| Representation | Monetary type | Date field | Item container |
|---|---|---|---|
| `Receipt` | `double totalAmount` | `DateTime date`, `String time` | `List<ReceiptItem> items` |
| `ReceiptModel` | `double totalAmount` | `DateTime date`, `String time` | `List<ReceiptItemModel> items` |
| `ReceiptModel.toJson()` | `total_amount` (number) | `date` and `scanned_date` (UTC ISO-8601) | `items` (list of maps) |
| `public.receipts` row | `NUMERIC(12,2)` | `scanned_date TIMESTAMPTZ`, `transaction_time TEXT` | none; items belong to `public.receipt_items` |

The `date` and `items` keys have no corresponding columns, so the push in Section 5 is rejected by
PostgREST (`TAIDY-C03`, issue #4).

## 2. Session Establishment

```
 LoginPage                AuthNotifier                 Supabase Auth          Router
 ---------                ------------                 -------------          ------
 signIn(email, pw) ---->  status = loading
                          repository.signInWithEmailPassword(...)
                                         -----------------> signInWithPassword
                                         <----------------- Session, User
                          [rememberMe] write refresh token and session JSON to secure storage
                          status = authenticated
                          RouterNotifier.notifyListeners() ----------------------> redirect():
                                                                                 initial sync not done
                                                                                 -> /sync_progress
 SyncProgressPage.initState -> SyncProgressNotifier.startInitialSync(userId)  (Section 8)
                          initialSyncCompletedProvider = true -------------------> redirect(): -> /home
```

| Step | Function | Output | Failure behaviour |
|---|---|---|---|
| 1 | `AuthNotifier.signIn` | `AuthState(status: loading)` | none |
| 2 | `AuthRepositoryImpl.signInWithEmailPassword` | `Either<AuthFailure, User?>` | exception mapped by `_mapException`; unknown errors are reported as `InvalidCredentialsFailure` |
| 3 | secure storage writes | refresh token, serialized session, remember-me flag | exceptions propagate to the repository catch block |
| 4 | `AuthNotifier` state update | `AuthState(status: authenticated, user)` | none |
| 5 | `routerProvider` redirect | `/sync_progress` | none |
| 6 | `SyncEngine.executeSync` | local boxes populated | Section 8 |

Unauthenticated use is supported: when no user identifier is available, `SyncProgressPage` marks
initial synchronization as complete and navigates onward, and `SyncManager.syncAll` returns early.

## 3. Receipt Capture and Extraction

Entry point: `ScanPage._pickImage(ImageSource source)`
(`lib/features/receipt_scanning/presentation/pages/scan_page.dart`).

| Step | Function | Input | Output | Failure behaviour |
|---|---|---|---|---|
| 1 | `_checkAndRequestPermission(source)` | camera or gallery | `bool` | returns to idle state |
| 2 | `ImagePicker.pickImage(maxWidth: 1920, maxHeight: 1920, imageQuality: 85)` | user selection | `XFile` in the platform cache directory | `null` returns to idle |
| 3 | `ref.read(receiptRepositoryProvider).processReceiptImage(image.path, taxonomy: taxonomy)` | file path, current taxonomy from `taxonomyProvider` | `Either<Failure, Receipt>` | `Left` shows a SnackBar |
| 4 | `ReceiptRepositoryImpl.processReceiptImage` | delegates to `aiService.extractReceiptData` | as above | backend-specific |
| 5 | `TelemetryService.recordInferencePerformance(...)` | elapsed time | JSON-lines event | errors ignored |
| 6 | `context.push('/review', extra: receipt)` | `Receipt` | ReviewPage | none |

The image remains at the picker's cache path; it is not copied to durable storage
(`TAIDY-M10`, issue #32). The confidence value shown after step 3 is computed by the page from field
presence, not reported by a model (`TAIDY-L05`, issue #50).

### 3.1 Backend-specific extraction

| Backend | Pipeline | Output identifier and date |
|---|---|---|
| `VlmEngineService` | read bytes; `EpisodicMemoryService.buildFewShotPromptSection(limit: 3)`; `VlmWorkerIsolate.processImage`; `jsonDecode`; `_mapJsonToReceiptModel` | `vlm_<milliseconds>`; `DateTime.parse(json['date'])`, falling back to now |
| `LLMService` | ML Kit OCR (main isolate); prompt assembly; `Isolate.run(_runLlamaInIsolate)`; `JsonParserUtils.extractJsonMap`; `_mapToReceipt` | `<milliseconds>`; always now (`TAIDY-H15`, issue #20) |
| `GeminiAIService` | read bytes; prompt with taxonomy; `GenerativeModel.generateContent`; `JsonParserUtils.extractJsonMap`; `ReceiptModel.fromJson` | `id` absent in model output, so `ReceiptModel.fromJson` assigns `<milliseconds>`; transaction date from JSON |
| `MockAIService` (`FallbackAIService`) | ML Kit OCR on Android and iOS with regular-expression parsing; otherwise synthesis from the file name | UUID v4; OCR date or now (`TAIDY-H12`, issue #17) |

### 3.2 VLM message flow across isolates

```
 main isolate                          worker isolate                    libreceipt_engine
 ------------                          --------------                    -----------------
 extractReceiptData(path)
   [worker not ready] initialize()
       generateAndSave(grammar)
       start(modelPath, grammarPath) -> spawn, _InitCommand ----------> receipt_engine_init
   bytes = File(path).readAsBytes()
   ctx = buildFewShotPromptSection(3)
   processImage(bytes, ctx) ---------> _ProcessImageCommand
                                          bindings.processImage(...)
                                            calloc image + 64 KiB output --> receipt_engine_process_image
                                                                               decodeImage, letterbox,
                                                                               build prompt, decode loop
                                          <------------------------------ status, NUL-terminated JSON
                       <---------------- String? json (timeout 45 s -> null)
   jsonDecode(json) -> Map<String, dynamic>
   _mapJsonToReceiptModel(map, path) -> ReceiptModel -> Receipt
   recordInferencePerformance(...)  (unawaited)
```

The native decode loop is compiled against placeholder symbols in current builds and terminates the
process when a model file is present (`TAIDY-C04`, issue #5).

## 4. Review and Local Commit

Entry point: `ReviewPage._saveReceipt()`
(`lib/features/receipt_scanning/presentation/pages/review_page.dart`).

```
 ReviewPage._saveReceipt
   |
   +-- updatedReceipt = widget.receipt.copyWith(merchantName, totalAmount, date, currency, items, boxId)
   +-- ReceiptListNotifier.addReceipt(updatedReceipt)
   |      +-- optimistic state update (replace by id or prepend)
   |      +-- ReceiptRepositoryImpl.saveReceipt(receipt)
   |             1. HiveReceiptDataSourceImpl.saveReceipt(ReceiptModel.fromEntity(receipt))   box receipts_v3
   |             2. OutboxService.enqueue(entityType: 'receipt', mutationType: 'upsert',
   |                                      payload: model.toJson())                          box sync_outbox
   |             3. unawaited(SyncService.scheduleUpload(receipt.id, receipt.imagePath ?? ''))  Section 6
   |             4. unawaited(WebhookService.sendWebhook(receipt))                          Section 10.1
   |             5. for each item with isAsset: create AssetModel (warrantyMonths: 24),
   |                assetsBox.put, OutboxService.enqueue(entityType: 'asset', ...)
   |      +-- on Left(failure): restore previous state (failure not returned to the page)
   +-- VlmEngineService.recordUserCorrection(...) for each categorized item   (unawaited)
   +-- DatasetContributionService.stageVerifiedReceipt(...)                     (unawaited)
   +-- context.go('/home')
```

Ordering rationale: the Hive write precedes the outbox enqueue so that a crash between the two leaves
a locally consistent record that is merely unsynchronized, rather than an outbox item referring to an
unsaved entity. The upload and webhook are fire-and-forget so that the review screen closes without
waiting for the network.

Known deviations: the total is parsed with `double.tryParse` and becomes 0.0 for comma decimals;
failures are not surfaced; corrections are recorded with identical raw and corrected names
(`TAIDY-M11`, issue #33). `ReceiptModel.fromEntity` sets `version = 1` and leaves `updatedAt` null, which
affects conflict resolution in Section 7 (`TAIDY-H04`, issue #9).

## 5. Outbound Replication: Outbox Push

Trigger: `SyncManager` subscribes to `Connectivity().onConnectivityChanged` at construction and calls
`syncAll()` for every event that does not contain `ConnectivityResult.none`. The settings page also
calls `syncAll()` from its "force sync" action.

```
 syncAll()
   _syncLock.synchronized:
     user = supabase.auth.currentUser ---- null --> return
     _flushOutbox(user.id)
       pending = outboxService.getPendingMutations()        // status pending or failed, FIFO by timestamp
       for item in pending:
         payload = copy(item.payload) + { user_id }
         table   = _mapEntityTypeToTable(item.entityType)   // unknown types map to 'receipts'
         delete  ? UPDATE table SET deleted_at, updated_at WHERE id AND user_id
                 : UPSERT table (payload); receipt -> _stageTier1TrainingLabels(payload)
         success ? markCompleted(id)                        // removes the item
                 : markFailed(id, error); break             // stops the whole flush
     _pullDeltas(user.id)                                   // Section 7
     settings.put('last_synced_at', now().toUtc())
     onSyncCompleted()  -> reload receipts, boxes, invoices, assets notifiers
```

| Entity type | Table | Payload source |
|---|---|---|
| `receipt` | `receipts` | `ReceiptModel.toJson()` |
| `box` | `boxes` | `BoxModel.toJson()` |
| `invoice` | `invoices` | `InvoiceModel.toJson()` |
| `asset` | `vault_assets` | `AssetModel.toJson()` |
| `profile` | `user_profiles` | not enqueued by any caller |
| `taxonomy` | `taxonomies` | not enqueued by any caller |

Retry state is stored on the item (`retryCount`, `lastAttemptAt`, `errorMessage`). After five failures the
item becomes `permanently_failed` and is skipped. `getPendingMutations` supports exponential backoff
(`1 << retryCount.clamp(0, 6)` seconds) when called with `respectBackoff: true`; `SyncManager` does not
pass it (`TAIDY-M03`, issue #25).

## 6. Outbound Replication: Attachment and Label Upload

Trigger: `ReceiptRepositoryImpl.saveReceipt` calls `SyncService.scheduleUpload(String receiptId, String
imagePath)` for every saved receipt; `SyncService` also processes its queue at construction and on
connectivity changes.

```
 scheduleUpload(id, path)
   _syncLock: if no queue entry has receiptId == id and id is not in flight:
                sync_queue.add(SyncItemModel(receiptId, imagePath, addedAt: now))
   syncPendingItems()
     _syncLock:
       offline? return
       for key in queue.keys (snapshot):
         skip if in flight, permanentlyFailed, retryCount >= 5, or before nextRetryTimestamp
         _uploadItem(item):
           receipt = local receipts where id == item.receiptId   (missing -> treat as done)
           use_google_drive_storage ? GoogleDriveService.uploadReceiptData(json, id, path)
                                    : SupabaseDataSourceImpl.uploadTrainingData(receipt, path)
         success: queue.delete(key)
         failure: queue.put(key, item.withFailedAttempt(error, jitterMs < 250))
```

`SyncItemModel.withFailedAttempt` computes the next attempt as `min(2 * 2^retryCount, 32)` seconds plus
jitter and marks the item `permanentlyFailed` when `retryCount` reaches 5.

`SupabaseDataSourceImpl.uploadTrainingData(Receipt receipt, String imagePath)` performs:

| Step | Operation | Object |
|---|---|---|
| 1 | `storage.from('training_data').uploadBinary(path, bytes, upsert: true)` | `<uid>/images/<receiptId><ext>` |
| 2 | `getPublicUrl(path)` | public URL string |
| 3 | `uploadBinary` of label JSON (`image_id`, `image_path`, `image_url`, `user_id`, `timestamp`, `ground_truth`, `meta`) | `<uid>/labels/<receiptId>.json` |
| 4 | `from('receipts').upsert(row)`; on `PGRST204` retry without `image_path` and `image_url` | `public.receipts` |

The `training_data` bucket is public and no consent flag is checked (`TAIDY-C01`, issue #2). Step 4
sends `date` and `items` and is rejected; the error is logged as "Supabase database receipts table
upsert notice".

## 7. Inbound Replication: Delta Pull

`SyncManager._pullDeltas(String userId)` runs after the push within the same `syncAll` cycle.

```
 lastSyncedAt = settings['last_synced_at']   (device clock, written at the end of the previous cycle)
 for table in [receipts, boxes, invoices, vault_assets]:
   rows = SELECT * FROM table WHERE user_id = userId [AND updated_at > lastSyncedAt]
   for row in rows:
     row.deleted_at != null  -> local box.delete(row.id)
     local == null or _shouldRemoteOverwrite(local.updatedAt, local.version,
                                             remote.updatedAt, remote.version)
                             -> local box.put(row.id, Model.fromJson(row))
```

`_shouldRemoteOverwrite` returns true when the remote version is greater, false when it is smaller,
and otherwise compares `updatedAt`, treating a null local value as older. Because the server increments
`version` on every update and the client does not, remote rows generally win (`TAIDY-H04`, issue #9).
The watermark and the absence of pagination can skip or truncate rows (`TAIDY-H03`, issue #8).

## 8. Inbound Replication: Initial Full Replication

`SyncEngine.executeSync({required String userId, bool isInitial = true})` returns `Future<bool>` and
emits `SyncProgressState` values on `stateStream`.

```
 idle
  |
  v
 authenticating (0.05) -- advisory connectivity check
  |
  v
 fetchingManifest (0.15) -- fetchReceipts, listRemoteFiles, fetchBoxes, fetchAssets, fetchInvoices
  |                         (12 s timeout per call; errors yield empty lists)
  v
 downloadingDeltas (0.25 .. 0.90)
  |   receipts absent locally   -> _parseReceiptFromRow -> localDataSource.saveReceipt
  |   all boxes, assets, invoices -> _parse*FromRow -> box.put  (overwrites)
  v
 rehydratingStorage -- for each <uid>/images/* file: download (20 s timeout) to <documents>/<name>
  |                    unless a local file with the same size exists
  v
 SyncService.syncPendingItems()   (push queued uploads)
  |
  v
 verifyingParity (0.95) -- fixed 300 ms delay
  |
  v
 completed (1.0) --> SyncProgressNotifier sets initialSyncCompletedProvider = true
                     and invalidates receiptListProvider

 any exception: attempt < 5 -> interruptedRetrying, wait pow(2, attempt).clamp(2, 10) s + jitter, retry
                attempt == 5 or cancelled -> failed (canContinueOffline = true)
```

The private row parsers read `date`, `color` and `icon`, which are not schema columns, and soft-deleted
rows are not filtered (`TAIDY-H05`, issue #10). The gate runs on every cold start (`TAIDY-M08`,
issue #30).

## 9. Deletion

| Operation | Local effect | Outbox effect | Direct remote effect |
|---|---|---|---|
| `ReceiptRepositoryImpl.deleteReceipt(id)` | `receipts_v3.delete(id)` | `delete` tombstone for `receipt` | `deleteData([id])` removes `<uid>/images/<id>.jpg` and `<uid>/labels/<id>.json` |
| `clearAllData(includeCloud: false)` ("Device Only") | `receipts_v3.clear()` | `delete` tombstone for every receipt | none |
| `clearAllData(includeCloud: true)` ("Everywhere") | `receipts_v3.clear()` | `delete` tombstone for every receipt | `deleteData(ids)` then hard `DELETE FROM receipts WHERE id IN (...)` in chunks of 100 |
| `BoxesNotifier.deleteBox(id)` (not `main`) | `boxes.delete(id)`; active box reset to `main` | `delete` tombstone for `box` | none |
| `InvoicesNotifier.delete(id)` | `invoices.delete(id)` | `delete` tombstone for `invoice` | none |
| `AssetNotifier.deleteAsset(id)` | `assets.delete(id)` | `delete` tombstone for `asset` | none |

A tombstone becomes `UPDATE ... SET deleted_at = now()` on push; other devices delete the record when
they pull it (Section 7). Consequences of the current design:

- "Device Only" deletes cloud data through the tombstones (`TAIDY-C02`, issue #3).
- Storage deletion assumes the `.jpg` extension (`TAIDY-M20`, issue #42).
- Hard-deleted rows are never observed by other devices (`TAIDY-M20`).
- Receipts that referenced a deleted box are not reassigned (`TAIDY-M09`, issue #31).

## 10. Secondary Pipelines

### 10.1 Webhook delivery

`WebhookService.sendWebhook(Receipt receipt)`:

1. Throws `WebhookFailure('Webhook is disabled')` when `webhook_enabled` is false; the repository
   catches and logs it.
2. Reads `webhook_url` from the settings box; returns when empty.
3. Reads `webhook_secret` from secure storage.
4. `POST <url>` with body `ReceiptModel.fromEntity(receipt).toJson()` and headers `Content-Type:
   application/json`, `User-Agent: tAIdy/1.0` and, when set, `X-Auth-Secret: <secret>`.
5. Maps errors with `ErrorHandler.mapException` and rethrows.

The URL is removed from the settings box on every launch (`TAIDY-M01`, issue #23).

### 10.2 CSV import

`ReceiptListNotifier.importCsvTransactions(String csvString, CsvParserService parser)` calls
`CsvParserService.importCsv`, which returns `Either<CsvParsingFailure, CsvImportReport>`:

1. Parse with `CsvToListConverter(eol: '\n')`, falling back to `'\r\n'`.
2. Skip the first row when it contains header keywords and lacks a parsable date or amount.
3. For each row, take the first cell that parses as a date, the first that parses as an amount, and
   concatenate the remaining non-numeric cells as the description.
4. Create one `Receipt` per valid row with a single item, `currency: 'USD'` and the absolute amount.
5. Save each receipt through `saveReceipt` (Section 4), so every imported row also enters the outbox
   and the upload queue.

Amount and date parsing are locale-dependent (`TAIDY-H14`, issue #19).

### 10.3 Export

`ExportService.exportReceiptsToCsv`, `exportReceiptsToJson` and `exportInvoicesToCsv` write a file to the
application documents directory (`<prefix>_<milliseconds>.csv` or `.json`) and open the platform share
sheet through `Share.shareXFiles`. CSV rows are flattened to one row per receipt item. Files are not
removed after sharing (`TAIDY-M13`, issue #35); cells are not neutralized against spreadsheet formulas
(`TAIDY-L02`, issue #47).

### 10.4 Invoices and boxes

`InvoicesNotifier.createInvoice(...)` computes `INV-<yyyy><mm>-<nnnn>` from local data and the
`global_invoice_counter` setting, rejects duplicates present locally, writes the invoice to Hive and
enqueues an `upsert`. `BoxesNotifier.createNew(...)` assigns a UUID v4, writes to Hive and enqueues an
`upsert`. Both follow the local-first order of Section 4.

### 10.5 Model download

`SupabaseModelRepository.downloadModelWithResume(...)` streams the file to `<name>.part`, resumes with an
HTTP `Range` header when a partial file exists, verifies SHA-256 against `LocalModelInfo.expectedSha256`,
and renames the file atomically. The configured digests do not correspond to the published files
(`TAIDY-H16`, issue #21). A separate updater, `ModelUpdateService`, downloads from a URL read from the
`app_config` table without verification (`TAIDY-H11`, issue #16).

## 11. AI Output Normalization

Language models frequently emit JSON wrapped in prose or Markdown, or truncated by token limits.
`JsonParserUtils.parseJsonSafe(String response)` returns `Either<ParsingFailure, Map<String, dynamic>>`
and is used by the Gemini and legacy LLM paths. It escalates through progressively more invasive
stages and stops at the first successful decode:

```
 response
   |
   v
 extractJsonBlock: fenced block if present, else first '{' to last '}' (or to end if unclosed)
   |
   v
 stage 1: jsonDecode(block) ----------------------------- Map --> Right(map)
   | fails
   v
 stage 2: repairJson(block)
          1 strip // and /* */ comments
          2 None/True/False -> null/true/false
          3 close quotes on lines ending in an unterminated "key": "value,
          4 escape raw newlines, carriage returns and tabs inside strings
          5 remove trailing commas
          6 append missing closing brackets and braces
          7 remove trailing commas again
        jsonDecode ------------------------------------- Map --> Right(map)
   | fails
   v
 stage 3: _aggressiveRepair: convert single-quoted tokens to double quotes, repair again
        jsonDecode ------------------------------------- Map --> Right(map)
   | fails
   v
 Left(ParsingFailure('Failed to decode JSON after repair attempts', block))
```

The staged design preserves well-formed input unchanged while recovering common defects. Stage 2 is
not string-aware for steps 1 and 2 and can alter string content (`TAIDY-L03`, issue #48). The VLM path
does not use this utility because grammar-constrained decoding is intended to make repair unnecessary;
it calls `jsonDecode` directly and reports `ParsingFailure` on error.

The mapping from model JSON to `ReceiptModel` differs by backend:

| Field | Gemini (`ReceiptModel.fromJson`) | VLM (`_mapJsonToReceiptModel`) | Legacy LLM (`_mapToReceipt`) |
|---|---|---|---|
| merchant | `merchant_name` or `merchant.name` | `merchant_name` | `merchantName` |
| date | `scanned_date`, `date` or `transaction.date` | `date` | not read |
| total | `total_amount` or `transaction.total_amount` | `total_amount` | `totalAmount` |
| currency default | `USD` | `USD` | `EUR` |
| item name | `description` | `normalized_name`, then `raw_name`, then `description` | `description` |
| item unit price | `unit_price` | `unit_price` | `unitPrice` |

## 12. Data Inventory and Retention

| Data | Created by | Stored in | Transmitted to | Removed by |
|---|---|---|---|---|
| Receipt record | review save, CSV import, pull | `receipts_v3` (encrypted) | `public.receipts` via outbox; label JSON via `SyncService`; webhook | `deleteReceipt`, `clearAllData` |
| Receipt image | image_picker | platform cache directory | `training_data` bucket (public) or Google Drive | not removed locally; remote removal assumes `.jpg` |
| Line items | extraction, review | inside `ReceiptModel` | label JSON, webhook, `receipt_training_labels` (client staging) | with the receipt |
| Box, invoice, asset | notifiers | `boxes`, `invoices`, `assets` (encrypted) | `boxes`, `invoices`, `vault_assets` via outbox | notifier delete methods |
| Preferences and balances | settings UI | `settings` (not encrypted) | none | not removed by "Clear All Data" |
| Category taxonomy | taxonomy editor | `taxonomy_config` (not encrypted) | none | not removed |
| Corrections | review save | SQLite episodic memory (not encrypted) | none | not removed |
| Training records | review save | `dataset_contributions.jsonl` | none (export only) | `DatasetContributionService.clearStagedData()` |
| Telemetry | global error handlers, inference | ring buffer, `telemetry_events.jsonl` | none | `TelemetryService.clearLogs()` |
| Session tokens | authentication | secure storage and Supabase client storage | Supabase Auth | `signOut`, `purgeAuthData` |
| API keys and webhook secret | settings UI, `.env` | secure storage; `.env` asset in the bundle | Gemini, webhook endpoint | `SecureStorageService.clearAll()` |
