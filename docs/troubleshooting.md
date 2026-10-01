# tAIdy Troubleshooting Guide

This guide describes how to diagnose and resolve failures in tAIdy (EconomyApp) as implemented at
revision `c66e079`. It covers the triage procedure, the diagnostic sources available on the device and
on the backend, configuration errors, and the failure modes of each subsystem. Each failure mode is
written as Symptom, Root cause, Diagnosis and Resolution. Where the failure originates in a defect
rather than in configuration, the entry cites the audit finding in `audit/findings_report.md` and its
tracking issue; the resolution then describes the operational workaround, and the issue holds the code
change.

Component names and data paths follow `docs/architecture.md` and `docs/data_flow.md`.

## Contents

1. [Triage Procedure](#1-triage-procedure)
2. [Diagnostic Sources](#2-diagnostic-sources)
3. [Configuration Errors](#3-configuration-errors)
4. [Startup and Local Storage](#4-startup-and-local-storage)
5. [Authentication and Access Control](#5-authentication-and-access-control)
6. [Receipt Extraction](#6-receipt-extraction)
7. [Synchronization](#7-synchronization)
8. [Build, Packaging and Continuous Integration](#8-build-packaging-and-continuous-integration)
9. [Data Preservation Before Intervention](#9-data-preservation-before-intervention)
10. [Reporting a Defect](#10-reporting-a-defect)

---

## 1. Triage Procedure

Most failures in tAIdy are silent: errors are caught, logged with `debugPrint` and converted to
default values, empty lists or a retry entry. The user interface therefore rarely shows the cause. The
procedure below locates the failing stage first and only then examines its cause, because the same
visible symptom (for example, "my receipt is not on my other device") can originate in four different
stages.

```
 Step 1  Reproduce with a debug or profile build attached to a console
         (flutter run, flutter logs, or adb logcat -s flutter)
            |
            v
 Step 2  Identify the first stage that does not produce its expected output
            |
            +-- application does not reach the login screen ---------> Section 4
            +-- login fails, or the app loops through /sync_progress -> Section 5
            +-- scan produces no receipt, wrong data, or a crash ---> Section 6
            +-- receipt saved locally but absent remotely or on
            |   another device, or local data changes unexpectedly -> Section 7
            +-- build, packaging or CI failure ---------------------> Section 8
            |
            v
 Step 3  Match the console output against the log index (Section 2.1)
            |
            v
 Step 4  Before deleting, clearing or resetting anything, follow Section 9
```

Stage boundaries are observable as follows:

| Stage | Evidence that the stage completed |
|---|---|
| Bootstrap | the login page or home page renders; no `FATAL ... Box Corruption` line |
| Authentication | `Auth Event: AuthChangeEvent.signedIn` (or `initialSession` with a user) |
| Initial replication | `/sync_progress` shows completion and navigates to `/home` |
| Extraction | the review page opens with populated fields |
| Local commit | `OutboxService: Enqueued mutation upsert for receipt (<id>)` |
| Outbox push | `OutboxService: Mutation <id> synced and removed from outbox.` |
| Attachment upload | `SyncService: Synced receipt <id>` |
| Remote persistence | a row exists in `public.receipts` (Section 2.4) |

## 2. Diagnostic Sources

### 2.1 Console log index

All components log through `debugPrint`. The prefix identifies the emitting component.

| Prefix or message | Component | Source |
|---|---|---|
| `Warning: Could not load .env, attempting fallback` | bootstrap | `lib/main.dart` |
| `Warning: Supabase initialization deferred/offline mode` | bootstrap | `lib/main.dart` |
| `FATAL Settings Box Corruption`, `FATAL Database Box Corruption` | bootstrap | `lib/main.dart` |
| `HiveMigrationService [DIAGNOSTIC]:` | box opening and backup | `lib/core/services/hive_migration_service.dart` |
| `SecureStorage: Generated new Hive encryption key.` | key management | `lib/core/services/secure_storage_service.dart` |
| `Auth Event:`, `Session recovery failed:` | authentication | `lib/features/auth/presentation/providers/auth_provider.dart` |
| `SyncEngine:` | initial replication | `lib/features/sync/data/datasources/sync_engine.dart` |
| `RemoteReplica:` | initial replication queries | `lib/features/sync/data/datasources/remote_replica_data_source.dart` |
| `SyncManager:` | outbox push and delta pull | `lib/core/sync/sync_manager.dart` |
| `OutboxService:` | outbox state transitions | `lib/core/sync/outbox_service.dart` |
| `SyncService:` | attachment upload queue | `lib/features/receipt_scanning/data/datasources/sync_service.dart` |
| `Supabase upload:`, `Supabase database receipts table upsert notice:` | attachment upload | `lib/features/receipt_scanning/data/datasources/supabase_data_source.dart` |
| `VlmEngineService:`, `VlmWorkerIsolate:`, `VlmFfiBindings:` | on-device VLM | `lib/core/services/vlm/` |
| `LLM:`, `LLM Extract Error:`, `OCR:` | legacy on-device LLM | `lib/core/services/llm_service_mobile.dart` |
| `Gemini AI Error:`, `Gemini: Failed to extract JSON from response` | cloud extraction | `lib/features/receipt_scanning/data/datasources/gemini_ai_service.dart` |
| `FallbackAIService` | heuristic fallback | `lib/features/receipt_scanning/data/datasources/mock_ai_service.dart` |
| `JsonParserUtils:` | model output repair | `lib/core/utils/json_parser_utils.dart` |
| `TelemetryService:` | telemetry persistence | `lib/core/services/telemetry_service.dart` |

`debugPrint` is not compiled out of profile or release builds. Console output is available on Android
through `adb logcat -s flutter`, on iOS through the device console (Xcode or Console.app), and on
desktop through the terminal that launched the application. When a failure reproduces only in a
release build, a profile build (`flutter run --profile`) uses release-mode compilation while keeping
the application attached to the tool.

### 2.2 Telemetry log

`TelemetryService` records uncaught framework errors (`FlutterError.onError`), uncaught asynchronous
errors (`PlatformDispatcher.instance.onError`) and inference timings. Events are kept in an in-memory
ring buffer of 100 entries and appended as JSON lines to `<documents>/logs/telemetry_events.jsonl`.

Two properties matter during triage:

- The asynchronous error handler returns `true`, which marks every uncaught asynchronous error as
  handled. The application therefore continues in a possibly inconsistent state instead of
  terminating, and the telemetry file may be the only record of the error (`TAIDY-L04`, issue #49).
- Native faults in `libreceipt_engine` (segmentation faults, illegal instructions) terminate the
  process before any Dart handler runs and are not recorded. Use `adb logcat` (Android, tag `DEBUG`
  for tombstones) or the operating system crash reporter instead.

### 2.3 On-device file locations

`<documents>` denotes the directory returned by `getApplicationDocumentsDirectory()`; `<support>`
denotes `getApplicationSupportDirectory()`.

| Data | Location |
|---|---|
| Hive boxes (`settings.hive`, `receipts_v3.hive`, `sync_queue.hive`, `assets.hive`, `boxes.hive`, `invoices.hive`, `sync_outbox.hive`, `taxonomy_config.hive`) and their `.lock` files | `<documents>` on all non-web platforms (`Hive.initFlutter`) |
| Automated box backups | `<documents>/hive_backups/` on Android and iOS; `<support>/hive_backups/` on desktop |
| Model files | `<documents>/models/` |
| Generated GBNF grammar | `<documents>/grammars/` |
| Episodic memory database | `<documents>/memory/episodic_memory.db`, `<documents>/memory/hnsw_rag.bin` |
| Training contributions | `<documents>/dataset_contributions/dataset_contributions.jsonl` |
| Telemetry | `<documents>/logs/telemetry_events.jsonl` |
| Exports | `<documents>/<prefix>_<milliseconds>.csv` or `.json` |
| Captured images | platform cache directory chosen by `image_picker` |
| Encryption key, API keys, session | platform secure storage (`flutter_secure_storage`) |

Typical values of `<documents>`:

| Platform | Path |
|---|---|
| Android (`com.taidy.finance`) | `/data/data/com.taidy.finance/app_flutter`; readable with `adb shell run-as com.taidy.finance` on debuggable builds only |
| iOS | the `Documents` directory of the application container (Xcode, Devices and Simulators, Download Container) |
| macOS (sandboxed, `com.example.tAidy`) | `~/Library/Containers/com.example.tAidy/Data/Documents` |
| Linux (`com.example.t_aidy`) | the XDG documents directory, typically `~/Documents` |
| Windows | the user's `Documents` folder |

On Linux and Windows the Hive files are therefore written directly into the user's Documents folder,
next to unrelated user files. Do not clean that folder without first identifying the files listed above.

### 2.4 Backend diagnostics

Run the following read-only queries in the Supabase SQL editor. Replace `<uid>` with the user
identifier shown in Authentication, Users.

```sql
-- Does the user have any synchronized receipts, and when was the latest change?
SELECT count(*) AS receipts, max(updated_at) AS latest
FROM public.receipts
WHERE user_id = '<uid>';

-- Which columns does PostgREST expose for receipts? (compare with the payload keys, Section 7.1)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'receipts'
ORDER BY ordinal_position;

-- Which buckets exist and which are public?
SELECT id, public FROM storage.buckets ORDER BY id;

-- Which storage policies are active?
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects';

-- Is a shared identifier owned by another tenant? (Section 7.2)
SELECT id, user_id FROM public.boxes WHERE id = 'main';

-- Does the table read by the OTA model updater exist? (Section 6.4)
SELECT to_regclass('public.app_config');
```

Supabase also records rejected PostgREST requests under Logs, API; filter by status 400 to find schema
mismatches and by status 401 or 403 to find policy rejections.

## 3. Configuration Errors

### 3.1 Build fails because `.env` is missing

**Symptom.** `flutter run` or `flutter build` stops during asset bundling with an error stating that no
file was found for the asset `.env`.

**Root cause.** `pubspec.yaml` declares `.env` and `.env.example` as assets. `.env` is excluded by
`.gitignore`, so a fresh clone does not contain it, and Flutter refuses to build with a declared asset
that does not exist.

**Resolution.** Create the file from the tracked template before building:

```bash
cp .env.example .env
```

Then set the values described in Section 3.2. The CI workflows (`ci.yml`, `gh-pages.yml`) perform the
same copy step. At runtime, `main.dart` loads `.env` and falls back to `.env.example` if loading fails.

Every key in `.env` is copied verbatim into the application bundle (APK assets, IPA, web output) and
can be extracted from a distributed build (`TAIDY-M14`, issue #36). Only values that are public by
design may be placed there: the Supabase project URL and the anon key. Never place the Supabase
`service_role` key or OAuth client secrets in `.env`.

### 3.2 Supabase credentials are absent or placeholders

**Symptom.** Sign-in fails with a network error that mentions `placeholder.supabase.co` or a host
lookup failure; or the application shows errors on first use of any cloud feature after logging
`Warning: Supabase initialization deferred/offline mode`.

**Root cause.** `main.dart` reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from the loaded environment and
substitutes `https://placeholder.supabase.co` and `placeholder-anon-key` when either is missing.
`Supabase.initialize` succeeds with the placeholder values, and every request then fails DNS
resolution. If `Supabase.initialize` itself throws (for example, a malformed URL), the error is logged
and startup continues, but `supabaseDataSourceProvider`, `modelRepositoryProvider`,
`remoteReplicaDataSourceProvider` and `AuthRepositoryImpl` read `Supabase.instance.client` without a
guard and fail on first use (`TAIDY-M05`, issue #27).

**Diagnosis.** Search the console for the two warnings above. Confirm the values in the bundled `.env`.

**Resolution.** Set both keys in `.env`:

```
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=<anon public key from Project Settings, API>
```

Rebuild the application; `.env` is an asset, so a hot restart does not pick up changes.

### 3.3 Variables in `.env.example` that have no effect

`.env.example` lists `GEMINI_API_KEY` and `WEBHOOK_SECRET`, but no code reads them. The Gemini key is
read only from secure storage (key `gemini_api_key`) and is entered in Settings. The webhook secret is
read only from secure storage (key `webhook_secret`) and is entered on the Integrations page.
`GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are read by `GoogleDriveService`.

### 3.4 Gemini is configured but not used

**Symptom.** A Gemini key has been entered, yet extraction results do not come from Gemini.

**Root cause.** `aiServiceProvider` selects the first available backend in a fixed order: on-device VLM
(`isVlmReadyProvider`), legacy on-device LLM (`isLlmLoadedProvider`), Gemini (only when the setting
`enable_gemini_ai` is `true` and the key is non-empty), and finally `MockAIService`. Gemini is used only
when both on-device engines are not ready. `enable_gemini_ai` defaults to `false`.

**Resolution.** Enable the Gemini toggle in Settings in addition to entering the key. If an on-device
model file is present in `<documents>/models/`, an on-device backend takes precedence. See also Section
6.6 for Gemini-specific errors.

### 3.5 Webhook deliveries stop after a restart

**Symptom.** Webhooks are delivered after configuration but stop after the application restarts; no
error is shown.

**Root cause.** The Integrations page stores `webhook_url` in the settings box, and `WebhookService`
reads it from there. At every launch, `_migrateSecretsToSecureStorage` moves `webhook_url` from the
settings box to secure storage and deletes the Hive entry. `sendWebhook` then finds no URL and returns
without error (`TAIDY-M01`, issue #23).

**Resolution.** Re-enter the URL after each launch until the defect is fixed. The secret is unaffected.
Use an `https://` endpoint; the secret is sent verbatim in the `X-Auth-Secret` header.

### 3.6 Backend schema is missing, outdated or diverges from the client

**Symptom.** PostgREST errors such as `PGRST204` ("Could not find the '<column>' column of '<table>' in
the schema cache"), `PGRST205` or PostgreSQL `42P01` ("relation does not exist").

**Root cause.** Either the schema has not been applied to the project, the PostgREST schema cache is
stale after a migration, or the client sends keys that the schema does not define. The last case is a
client defect for the `receipts` table (Section 7.1).

**Diagnosis.** Run the column query in Section 2.4 and compare it with the column named in the error.

**Resolution.**

1. Apply `supabase/migrations/20260828_master_sync_schema.sql` and then
   `supabase/migrations/20260828_color_hex_bigint.sql` in order. `supabase/schema.sql` is identical to
   the first migration and need not be applied separately.
2. Reload the PostgREST schema cache:

   ```sql
   NOTIFY pgrst, 'reload schema';
   ```

3. If the reported column is `date`, `items` or `image_url` on `receipts`, the schema is correct and the
   error is the client defect described in Section 7.1. Do not add these columns to work around it:
   `items` belongs in `public.receipt_items`, and adding `image_url` would persist public object URLs
   (`TAIDY-C01`, issue #2).

Earlier versions of this guide recommended adding `image_path` to `receipts`. The column is already
part of the schema.

### 3.7 Storage requests are rejected with 403

**Symptom.** `Supabase upload failed: StorageException(... new row violates row-level security policy,
statusCode: 403 ...)`.

**Root cause.** The schema defines three buckets, `receipt_images` (private), `asset_documents`
(private) and `training_data` (public), each with a policy that admits an authenticated user only when
the first path segment equals the user identifier: `(storage.foldername(name))[1] = auth.uid()::text`.
A 403 indicates that the bucket or policy was not created, that the request was made without a session,
or that the object path does not begin with `<uid>/`. There is no bucket named `receipts`; policies
written for such a bucket have no effect.

**Diagnosis.** Run the bucket and policy queries in Section 2.4. Confirm that a user is signed in when
the upload runs (`SyncService` uploads use the current session).

**Resolution.** Re-apply section 7 of the master migration ("Storage Buckets & Isolation Policies"). Do
not widen the policies to `FOR ALL TO authenticated` without the folder predicate: that would let every
user read and overwrite every other user's objects.

### 3.8 Release build is signed with the debug key

**Symptom.** A release APK installs over a debug build without a signature conflict, or an app store
rejects the upload as debug-signed.

**Root cause.** `android/app/build.gradle.kts` selects the debug signing configuration for the release
build type when neither `key.properties` nor the `STORE_FILE` environment variable is present
(`TAIDY-M16`, issue #38).

**Resolution.** Provide `android/key.properties` (or the corresponding environment variables in CI)
before producing release artifacts, and verify the signature with `apksigner verify --print-certs`.

## 4. Startup and Local Storage

### 4.1 "Data Recovery Required" screen

**Symptom.** At launch the application shows "Data Recovery Required" naming a box, and it shows the same
screen after every restart.

**Root cause.** `HiveMigrationService.openBoxSafe` failed to open the named box (corrupt file, wrong
encryption key, or a type adapter that cannot read the stored records). It copied the file to
`hive_backups/` and threw `SchemaCorruptionException`, which `main.dart` renders as `_DataRecoveryApp`.
The screen advises that a restart creates a fresh database, but the failed file is copied rather than
moved, so the next launch fails in the same way (`TAIDY-H07`, issue #12). On desktop platforms the
backup routine looks for the box under `<support>` while Hive stores it under `<documents>`, so no backup
is created and the screen reports that no backup exists.

**Diagnosis.**

1. Read the console line `HiveMigrationService [DIAGNOSTIC]: Failed to open "<box>": <error>`. The error
   distinguishes the causes:
   - an exception during decryption or a CRC or frame error on an encrypted box, together with
     `SecureStorage: Generated new Hive encryption key.` earlier in the same launch, indicates key loss
     (Section 4.3);
   - `HiveError` mentioning an unknown type identifier or adapter indicates an adapter registry problem
     (Section 4.4);
   - any other read error on a single box indicates file corruption.
2. Use "View Technical Details" on the recovery screen to obtain the box name, the cause and the backup
   path.

**Resolution.** Preserve data first (Section 9). Then, for single-box corruption with an intact key:

1. Close the application completely.
2. Copy `<box>.hive` and `<box>.lock` from `<documents>` to a safe location (on desktop, this copy
   replaces the backup that was not created).
3. Remove both files from `<documents>`.
4. Start the application. Hive creates an empty box with the same name.

The consequence depends on the box:

| Box | Content lost locally when removed | Recoverable from the backend |
|---|---|---|
| `settings` | preferences, budget values, `schema_version` (migrations run again) | no |
| `receipts_v3` | all receipts | only receipts present in `public.receipts`; see Section 7.1 |
| `sync_outbox` | unsynchronized changes of every entity type | no |
| `sync_queue` | pending attachment uploads | no; images are not re-queued |
| `boxes`, `invoices`, `assets` | the respective entities | yes, by initial replication, if they were pushed |
| `taxonomy_config` | custom category hierarchy | no |

### 4.2 Blank window or indefinite hang at launch

**Symptom.** The application window stays blank or the splash screen persists; no recovery screen is
shown.

**Root cause.** Two paths in `main` are not guarded. First, `SecureStorageService.getHiveEncryptionKey()`
is awaited without error handling; a failure of the platform keystore (Linux without a running Secret
Service provider, a locked keychain, an Android Keystore error) propagates out of `main` before
`runApp`. Second, `openBoxSafe` completes its result only from its inner `try`/`catch`; an error routed
to the surrounding zone handler is logged as `Intercepted secondary zone error` and leaves startup
waiting indefinitely (`TAIDY-H07`, issue #12).

**Diagnosis.** Run from a console. A keystore failure produces an unhandled exception from
`flutter_secure_storage`. A zone-routed error produces the `Intercepted secondary zone error` line and no
further bootstrap output.

**Resolution.** On Linux, ensure that a Secret Service provider (for example, GNOME Keyring or KWallet
with the Secret Service interface) is running and unlocked in the session. On other platforms, unlock
the device keychain and retry. For a zone-routed Hive error, treat the box named in the preceding
diagnostic line as corrupt and follow Section 4.1.

### 4.3 Encryption key loss

**Symptom.** Every encrypted box fails to open at once (typically `receipts_v3` is reported first because
it is opened first after `settings`), and the console shows `SecureStorage: Generated new Hive
encryption key.` on a device that already had data.

**Root cause.** The 256-bit key is stored in secure storage under `taidy_hive_encryption_key`. When the
key is absent, `getHiveEncryptionKey` generates a new key without checking whether encrypted boxes
already exist. Common triggers are Android Auto Backup restoring application files to a new device
(the manifest does not disable backup, and Keystore-bound key material is not restorable), clearing
secure storage, or reinstalling on iOS with a keychain reset.

**Resolution.** Data encrypted with the lost key cannot be decrypted with the new key. Do not remove the
box files while any chance of restoring the original key exists. If the original key cannot be
restored, the local data is unrecoverable; remove the encrypted box files as in Section 4.1 and restore
from the backend where possible. Note that receipts are generally absent from the backend (Section
7.1). The settings box is unencrypted and survives key loss.

### 4.4 Hive adapter errors after code generation

**Symptom.** After running `build_runner`, boxes fail to open or writes fail with a `HiveError` about an
unknown type or an adapter already registered for type identifier 12.

**Root cause.** Type identifier 12 is declared twice, by the `SyncStatus` enum and by `SyncOutboxItem`.
The checked-in adapters were edited by hand to avoid the collision: `SyncItemModelAdapter` stores
`status` as an integer index and `sync_outbox_item.g.dart` is a manual adapter. Regenerating the code
reintroduces the collision (`TAIDY-H06`, issue #11).

**Resolution.** Revert the regenerated `sync_item_model.g.dart` and `sync_outbox_item.g.dart` to the
committed versions (`git checkout -- <path>`) until the identifiers are reassigned. Do not change type
identifiers of existing types: records already written with the old identifier become unreadable. The
current registry is documented in `docs/architecture.md`, Section 5.

## 5. Authentication and Access Control

### 5.1 Every sign-in error is reported as invalid credentials

**Symptom.** Sign-in reports invalid credentials although the credentials are correct.

**Root cause.** `AuthRepositoryImpl._mapException` maps `AuthException` messages to specific failures by
keyword (invalid credentials, user not found, already registered, network). Any message that matches
none of these keywords, such as an unconfirmed e-mail address or a rate limit, is reported as
`InvalidCredentialsFailure`.

**Diagnosis.** The original server message is preserved in the failure; inspect it in a debug session, or
read the Auth logs in the Supabase dashboard for the same timestamp.

**Resolution.** Address the server-reported condition (confirm the address, wait for the rate limit
window, check the project's Auth settings).

### 5.2 Session is not restored after a restart

**Symptom.** The user must sign in again after every restart.

**Root cause.** Session restoration depends on the remember-me flag (`auth_remember_me` in secure
storage). When it is `false`, `AuthNotifier` deletes the persisted session at startup by design. When it
is `true` and restoration fails, the console shows `Session recovery failed: <message>` and the
notifier falls back to the Supabase client's current user, which may be absent.

**Resolution.** Select "remember me" at sign-in. If restoration still fails, the refresh token has
expired or was revoked; a new sign-in is required.

### 5.3 The application passes through `/sync_progress` on every launch

**Symptom.** After every cold start of a signed-in session, the replication screen runs before the home
page is reachable; offline, it can take considerably longer to complete.

**Root cause.** `initialSyncCompletedProvider` is an in-memory flag initialized to `false`; the router
redirects every authenticated session to `/sync_progress` until it becomes `true`. `SyncEngine` performs
a full replication each time, with a 12-second timeout per query and up to five attempts. Query errors
are converted to empty results, so an offline run waits for its queries to fail or time out and then
completes without remote data (`TAIDY-M08`, issue #30).

**Resolution.** Use "Continue Offline" to proceed with local data. The behaviour itself requires the
code change described in the issue.

### 5.4 Biometric lock is bypassed

**Symptom.** With biometric protection enabled, the application opens without a prompt on some devices.

**Root cause.** `BiometricGuard` treats "cannot authenticate" as success: when
`BiometricService.canAuthenticate()` returns `false`, including after an exception, the guard unlocks.
The enabling flag `biometric_auth_enabled` is stored in the unencrypted settings box (`TAIDY-H13`,
issue #18).

**Resolution.** Ensure that a biometric or device credential is enrolled on the device. The guard must
not be relied upon as a security boundary until the issue is resolved.

## 6. Receipt Extraction

### 6.1 Identifying the active backend

No user interface element shows which backend processed an image. Determine it from the console:

| Backend | Selected when | Console evidence |
|---|---|---|
| On-device VLM (`VlmEngineService`) | `isVlmReadyProvider` is `true` | `VlmWorkerIsolate: Persistent worker initialized successfully.` |
| Legacy LLM (`LLMService`) | `isLlmLoadedProvider` is `true` | `LLM: Ready (will load in isolate on demand)`; `OCR: Starting for <path>` during a scan |
| Gemini (`GeminiAIService`) | both on-device flags `false`, `enable_gemini_ai` `true`, key present | `Gemini ...` lines only on failure |
| Fallback (`MockAIService`) | none of the above | `FallbackAIService` lines on OCR failure; otherwise none |

The readiness flags are set by the startup post-frame task (legacy LLM only) and by the model manager
page (`/model_manager`), which initializes both engines when a model file is present.

### 6.2 Review screen shows plausible but invented data

**Symptom.** Merchant names such as "Fresh Grocery Supplies", Apple Store items, or a fixed Italian
supermarket receipt appear regardless of the image.

**Root cause.** In the default configuration (no on-device model, Gemini disabled),
`FallbackAIService` synthesizes a receipt from the file name when OCR is unavailable (desktop, web) or
yields no parsable text. On non-mobile platforms the legacy LLM path receives the fixed text "Simulated
Receipt Text" instead of OCR output (`TAIDY-H12`, issue #17). The native engine returns a hard-coded
fallback receipt when initialized with a model path that does not exist (`TAIDY-C04`, issue #5).

**Resolution.** Treat the fallback output as placeholder data and correct every field before saving, or
configure Gemini (Section 3.4). Do not save fabricated receipts: saved receipts are uploaded as
ground-truth training data (`TAIDY-C01`, issue #2).

### 6.3 The application terminates on the first scan after a model is installed

**Symptom.** The process exits without a Dart error during the first extraction after a model download.
`adb logcat` shows a native crash (`SIGSEGV`) in `libreceipt_engine.so`.

**Root cause.** Neither native build links llama.cpp. `receipt_engine.cpp` therefore compiles its
placeholder implementation of the llama.cpp API, whose batch allocator leaves `seq_id` unallocated; the
decode loop dereferences it (`TAIDY-C04`, issue #5). Native faults bypass all Dart error handlers.

**Resolution.** Remove the model file from `<documents>/models/` (and `mock_model_v2.gguf` from the
working directory on desktop) so that the VLM engine does not initialize; extraction then falls back to
the next backend. The on-device VLM path is not functional in current builds (`TAIDY-A05`, issue #62).

### 6.4 The on-device engine never becomes ready

**Symptom.** After a model download, extraction still uses a fallback backend.

**Diagnosis and resolution.** Work through the causes in order:

| Console evidence | Cause | Resolution |
|---|---|---|
| `VlmEngineService: No GGUF model found on disk.` | initialization without an explicit path (the lazy path taken by `extractReceiptData`) found neither `qwen2_vl_2b.Q4_K_M.gguf` nor `gemma-2b-it.Q4_K_M.gguf` in `<documents>/models/` | `smolvlm_500m.Q4_K_M.gguf` is used only when the model manager passes its path explicitly; open `/model_manager` again after each restart, or install Qwen2-VL |
| `Model checksum verification failed. The downloaded file is corrupt.` | the expected digests for Qwen2-VL and SmolVLM in `LocalModelInfo` are not genuine (`TAIDY-H16`, issue #21); every completed download of these models is discarded | none without a code change; the `.part` file is deleted after each attempt |
| `VlmFfiBindings: Could not load native library: ...` | `libreceipt_engine` is not packaged (Section 8.2) | build for a platform with native integration (Android, Linux, Windows) |
| `VlmWorkerIsolate: Error spawning worker isolate: TimeoutException ...` | native initialization exceeded 30 seconds (10 seconds for the isolate handshake) | the worker and the model allocation leak on timeout (`TAIDY-H10`, issue #15); restart the application before retrying |
| `VlmWorkerIsolate: Initialization failed on worker isolate.` | `receipt_engine_init` reported not ready | inspect native output; a vision-language model also requires a projector file, which is never provisioned (`TAIDY-H16`) |
| `LLM: Init Error: ...` | legacy LLM model lookup failed | confirm `gemma-2b-it.Q4_K_M.gguf` or `tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf` in `<documents>/models/` |

The separate OTA updater (`ModelUpdateService`) reads a download URL from the `app_config` table, which
the schema does not define; the update check fails at every launch. When the table is created, note that
the updater performs no integrity verification (`TAIDY-H11`, issue #16).

### 6.5 Extraction hangs or times out

**Symptom.** The scan page shows progress indefinitely, or a scan fails after about 45 seconds and later
scans are slow.

**Root cause.**

- `VlmWorkerIsolate.processImage` abandons a request after 45 seconds and returns `null`, but the worker
  continues the synchronous native call; the next request queues behind it (`TAIDY-H10`, issue #15).
- The streaming path awaits `StreamController.close()` before a listener exists and never completes when
  the native call ends without a completion callback (`TAIDY-H09`, issue #14).
- `LLMService.generate` never completes when the model constructor throws, because the constructor runs
  outside the region whose `finally` block sends the completion signal (`TAIDY-M23`, issue #45).

**Resolution.** Restart the application to terminate the worker. If the legacy LLM hangs, verify that the
model file is complete and not truncated (compare its size with the published size).

### 6.6 Gemini extraction errors

| Message | Cause | Resolution |
|---|---|---|
| `AI Quota Exceeded. Please wait a moment.` | the API returned a quota error | wait, or raise the quota of the API key |
| `Gemini AI Error:` with a model-not-found error | the service targets `gemini-1.5-flash`, which may be retired (`TAIDY-M12`, issue #34) | requires a code change to the model name |
| `AI returned empty response` | the model returned no text, for example after a safety block | retry with a clearer image |
| `Failed to parse AI output` | the response contained no recoverable JSON object (Section 11 of `docs/data_flow.md`) | retry; inspect `Gemini Raw Response:` |
| `Image file not found` | the image path no longer exists | rescan |

Images are always declared as `image/jpeg`; PNG and HEIC inputs may be rejected or misread
(`TAIDY-M12`). On the web platform the Gemini path reads image files through `dart:io` and does not
function.

### 6.7 Extracted values are wrong after saving

| Symptom | Cause | Reference |
|---|---|---|
| total saved as 0.00 | the review page parses the total with `double.tryParse`, which rejects decimal commas | `TAIDY-M11`, issue #33 |
| date is the scan date | the legacy LLM path discards the extracted date | `TAIDY-H15`, issue #20 |
| CSV import: wrong amounts, all positive, all USD, day and month swapped | locale-independent parsing, `abs()`, fixed currency, month-first dates | `TAIDY-H14`, issue #19 |
| unchanged items recorded as user corrections | raw and corrected names are identical | `TAIDY-M11` |

Correct the total with a decimal point instead of a comma until `TAIDY-M11` is resolved.

## 7. Synchronization

The synchronization paths are described in `docs/data_flow.md`, Sections 5 to 8. Three independent
mechanisms exist: the outbox (`SyncManager`), the attachment queue (`SyncService`) and initial
replication (`SyncEngine`). The Sync Center in Settings displays only the attachment queue; the outbox has
no user interface.

### 7.1 Receipts never reach the server or another device

**Symptom.** Receipts are visible on the capturing device but `public.receipts` contains no rows for the
user, and a second device shows no receipts after replication. Boxes, invoices and assets may synchronize
normally, or may also stall (Section 7.2).

**Root cause.** `ReceiptModel.toJson()` produces the outbox payload and includes the keys `date` and
`items`, which are not columns of `public.receipts`. PostgREST rejects the upsert with `PGRST204`. The
attachment path (`uploadTrainingData`) sends the same keys plus `image_url`; its fallback removes only
`image_path` and `image_url`, so the second attempt also fails and is logged as `Supabase database
receipts table upsert notice:` (`TAIDY-C03`, issue #4).

**Diagnosis.**

1. Console: `SyncManager: Failed to sync outbox item <id>: PostgrestException(... PGRST204 ...)` followed
   by `OutboxService: Mutation <id> failed (attempt N, status: failed)`.
2. Backend: the first query in Section 2.4 returns zero receipts for the user.
3. Supabase Logs, API: `POST /rest/v1/receipts` requests with status 400.

**Resolution.** None at the configuration level; do not add the missing columns (Section 3.6). Until
the defect is fixed, receipts exist only on the capturing device; protect them as described in Section 9
and do not rely on a second device or a reinstall to restore them.

### 7.2 The outbox is stalled for all entity types

**Symptom.** After one failure, later changes to boxes, invoices and assets are not pushed either.

**Root cause.** `SyncManager._flushOutbox` processes items in timestamp order and stops at the first
failure, so a failing item blocks every later item until it reaches five attempts and becomes
`permanently_failed`. Retry backoff exists in `OutboxService` but is not requested by `SyncManager`, so
every synchronization cycle retries the head item immediately and five cycles exhaust it regardless of
elapsed time. Items with an unknown entity type are written to `receipts` (`TAIDY-M03`, issue #25).
Because every receipt mutation fails (Section 7.1), each queued receipt blocks later items for five
cycles. A second common blocking item is an upsert of the default box `main` when another user already
owns a row with that identifier, which the row-level security policy rejects (`TAIDY-M02`, issue #24).

**Diagnosis.** Console: the same item identifier fails repeatedly with `OutboxService: Mutation <id>
failed (attempt N, ...)`. For the box case, the box query in Section 2.4 returns a row owned by a
different `user_id`.

**Resolution.** The queue drains once the blocking item becomes `permanently_failed`, which occurs after
five failed cycles. Permanently failed items are retained but never retried:
`OutboxService.retryPermanentlyFailed()` exists but no user interface calls it. Their changes therefore
remain local only.

### 7.3 Attachment uploads are marked "Failed" in the Sync Center

**Symptom.** Settings, Sync Center, shows "N Failed" and lists items under "Permanently Failed Uploads
(Max 5 attempts exceeded)".

**Root cause.** An upload failed five times; the backoff is `min(2 * 2^retryCount, 32)` seconds plus up
to 250 ms of jitter. The common cause is a storage policy rejection (Section 3.7). Missing image
files (Section 7.8) do not fail the item, because the upload proceeds with metadata only, and neither
does the receipt row rejection of Section 7.1, which is only logged. A permanently failed item also prevents the
same receipt from being scheduled again (`TAIDY-L08`, issue #53).

**Resolution.** Correct the underlying cause, then use "Manual Retry" on the item, which calls
`SyncService.retryFailedItem` and resets the retry count.

Before retrying, note that every upload places the receipt image and a label file in the public
`training_data` bucket regardless of the "AI Model Training Contribution" setting (`TAIDY-C01`, issue
#2). Enabling the Google Drive storage toggle (developer mode) redirects these uploads to Google Drive
instead.

### 7.4 Local edits are overwritten after synchronization

**Symptom.** An edit made on the device reverts to an earlier value after a synchronization cycle.

**Root cause.** The delta pull applies a remote row when its `version` is greater than the local
`version`. The server increments `version` on every update while the client never does, so the remote
row usually wins even when the local edit is newer and not yet pushed (`TAIDY-H04`, issue #9).

**Resolution.** Ensure the outbox has drained (no `OutboxService: Mutation ... failed` lines) before
editing the same record on another device. Re-apply the lost edit after the cycle completes.

### 7.5 Changes from another device are missing

**Symptom.** Some changes made on device A never appear on device B, although the rows exist remotely.

**Root cause.** The pull watermark `last_synced_at` is taken from the device clock after the pull
completes, so rows committed during the pull, or under clock skew, fall below the watermark and are
skipped. Queries are not paginated (`TAIDY-H03`, issue #8).

**Resolution.** Correct the device clock. To re-read the backend, use Settings, Sync Center, "Replicate
Cloud Data", which runs the initial replication (Section 7.6). It re-reads all boxes, invoices and
assets, and receipts that are absent locally; it does not update receipts that already exist locally.

### 7.6 Initial replication restores deleted records or loses fields

**Symptom.** After "Replicate Cloud Data" or a new sign-in, deleted boxes, invoices or assets reappear,
or box colours, icons and receipt dates are reset.

**Root cause.** The initial replication does not filter soft-deleted rows and overwrites local boxes,
invoices and assets without a conflict check. Its row parsers read `date`, `color` and `icon`, which are
not schema columns (`TAIDY-H05`, issue #10).

**Resolution.** Delete the resurrected records again; the deletion is pushed as a new tombstone. The
records reappear at the next full replication until the defect is fixed.

### 7.7 Replication remains in "interruptedRetrying" or ends in "failed"

**Symptom.** `/sync_progress` shows a retry countdown, or reports failure after several attempts.

**Root cause.** `SyncEngine.executeSync` retries up to five attempts with a delay of
`pow(2, attempt).clamp(2, 10)` seconds plus up to one second of jitter. The connectivity listener in
`SyncEngine` only logs `SyncEngine: Connectivity restored, resuming sync...`; it does not shorten or
restart the wait.

**Diagnosis.** `SyncEngine: Sync run failed on attempt N: <error>` gives the cause of each attempt.

**Resolution.** Use "Retry Sync" after connectivity returns, or "Continue Offline" to use local data.
Replication can be started again later from Settings, Sync Center, "Replicate Cloud Data".

### 7.8 Receipt images or warranty documents disappear

**Symptom.** Thumbnails and eVault documents are missing after some time or after a reinstall; uploads
log `Supabase upload: Image file empty or not found at "<path>", proceeding with metadata.`

**Root cause.** The image path stored with the receipt is the transient `image_picker` cache path; the
file is never copied to durable storage, and the operating system may evict it (`TAIDY-M10`, issue
#32).

**Resolution.** None after eviction. Images that were uploaded before eviction remain in the
`training_data` bucket under `<uid>/images/`.

### 7.9 Receipts disappear after a box is deleted

**Symptom.** After deleting a box, its receipts are no longer shown anywhere, although storage usage is
unchanged.

**Root cause.** `BoxesNotifier.deleteBox` does not reassign receipts that reference the deleted box, and
the dashboard shows only receipts of the active box (`TAIDY-M09`, issue #31).

**Resolution.** Recreating a box does not restore the association, because box identifiers are UUIDs.
The receipts remain in `receipts_v3`, but neither the dashboard nor the CSV export reaches them,
because the export also covers only the active box. Preserve `receipts_v3.hive` (Section 9) until the
issue is resolved.

### 7.10 "Device Only" data clearing removed cloud data

**Symptom.** After "Clear All Data", "Device Only", receipts are also removed from the backend and from
other devices.

**Root cause.** The device-only path clears the local box and enqueues a delete tombstone for every
receipt; the next push marks each remote row as deleted, and other devices remove the records when they
pull (`TAIDY-C02`, issue #3). The effect applies to receipts that reached the backend; while Section
7.1 is unresolved, few or none do, and the local clear is then the only copy lost.

**Resolution.** Do not use "Device Only" to free local storage until the issue is resolved. If it was
used, the remote rows are soft-deleted (`deleted_at` set) rather than removed. An administrator can
restore them by setting `deleted_at` to `NULL` for the affected identifiers; the `handle_updated_at`
trigger advances `updated_at` and `version`, so every device, including the one that was cleared,
retrieves the rows at its next delta pull.

## 8. Build, Packaging and Continuous Integration

### 8.1 Web build fails on `dart:ffi`

**Symptom.** `flutter build web` fails with errors such as `'Pointer' isn't a type` or an error that
`dart:ffi` is not available.

**Root cause.** Every library that imports `dart:ffi`, `package:llama_cpp_dart` or `sqlite3` must be
reachable only through a conditional import, because the web compiler rejects these libraries. The
current code follows this pattern:

| Facade | Native implementation | Web stub | Condition |
|---|---|---|---|
| `llm_service.dart` | `llm_service_mobile.dart` | `llm_service_stub.dart` | `dart.library.io` |
| `vlm_ffi_bindings.dart` | `vlm_ffi_bindings_ffi.dart` | `vlm_ffi_bindings_stub.dart` | `dart.library.ffi` |
| `vlm_worker_isolate.dart` | `vlm_worker_isolate_ffi.dart` | `vlm_worker_isolate_stub.dart` | `dart.library.ffi` |
| `episodic_memory_service.dart` | `episodic_memory_service_ffi.dart` | `episodic_memory_service_stub.dart` | `dart.library.ffi` |

A new direct import of an FFI-dependent library from any other file reintroduces the failure.

**Diagnosis.** The compiler error names the importing file. Locate direct imports with:

```bash
grep -rln "dart:ffi\|package:llama_cpp_dart\|package:sqlite3" lib
```

Only the native implementation files in the table above may appear in the output.

**Resolution.** Move the import into a native implementation file and expose it through a facade with a
conditional export, following the existing facades. The GitHub Pages workflow builds with
`--no-wasm-dry-run`.

### 8.2 Native library is missing or crashes on load

**Symptom.** `VlmFfiBindings: Could not load native library: ...`, or the process terminates with an
illegal instruction on an x86_64 machine.

**Root cause.** The library is built only where the platform build includes it:

| Platform | Build integration | Library name loaded |
|---|---|---|
| Android | `externalNativeBuild` with `android/app/src/main/cpp/CMakeLists.txt`; ABIs `arm64-v8a`, `armeabi-v7a`, `x86_64` | `libreceipt_engine.so` |
| Linux | `add_subdirectory(../native)` in `linux/CMakeLists.txt` | `libreceipt_engine.so` |
| Windows | `add_subdirectory(../native)` in `windows/CMakeLists.txt` | `receipt_engine.dll`, falling back to the process image |
| macOS, iOS | none | `libreceipt_engine.dylib`, falling back to the process image |

On macOS and iOS the fallback to the process image fails at symbol lookup, so the engine is unavailable.
On x86_64 targets the build enables AVX2 and FMA unconditionally; processors without AVX2 terminate with
an illegal instruction when engine code runs (`TAIDY-M15`, issue #37).

**Resolution.** Use a supported platform and an AVX2-capable x86_64 processor (or an ARM device). Native
build options are documented in `native/CMakeLists.txt`.

### 8.3 Continuous integration passes despite failures

**Symptom.** The "Flutter CI" workflow reports success while `flutter analyze` reports errors or tests
fail.

**Root cause.** `.github/workflows/ci.yml` sets `continue-on-error: true` on the analyzer step and runs
`flutter test || echo "No tests defined yet"`, which discards the test exit code. The default suite also
contains `test/core/sync/live_supabase_seeder_test.dart`, which requires live Supabase credentials
(`TAIDY-M16`, issue #38).

**Resolution.** Do not rely on the workflow status. Run the checks locally before opening a pull request:

```bash
cp .env.example .env    # if not present
flutter pub get
flutter analyze
flutter test
```

Inspect the step logs of the CI run for analyzer and test output.

### 8.4 Push rejected by secret scanning (GH013)

**Symptom.** `git push` fails with `remote: error: GH013: Repository rule violations found` and a
push-protection message identifying a secret, its file path and the commit that introduced it.

**Root cause.** A commit in the pushed range contains a credential, typically from `.env`,
`assets/credentials.json` or a hard-coded key. `.gitignore` excludes `.env`, `.env.*` (except
`.env.example`) and `assets/credentials.json`, but files added with `git add -f`, or added before the
ignore rule existed, remain tracked.

**Resolution.** Remove the secret from the unpushed commits only; do not delete the `.git` directory and
do not force-push over a shared branch.

1. Stop tracking the file while keeping the local copy:

   ```bash
   git rm --cached <path>
   ```

2. If the secret was introduced in the most recent commit, amend it:

   ```bash
   git commit --amend
   ```

   If it was introduced in an earlier unpushed commit, rewrite only the unpushed range
   (`git rebase -i @{upstream}`), editing the commit that added the file.
3. Confirm that no commit in the range still contains the value:

   ```bash
   git log -p @{upstream}..HEAD | grep -n "<distinctive part of the secret>"
   ```

4. Push again.
5. Rotate the credential at its issuer. The value has left the workstation and must be treated as
   exposed.

## 9. Data Preservation Before Intervention

Several resolutions in this guide remove local files. Because receipts currently exist only on the
capturing device (Section 7.1) and unsynchronized changes exist only in `sync_outbox`, collect the
following before any destructive step:

1. **Export.** If the application starts, use the download action on the home page, which exports the
   receipts of the active box as CSV; repeat for each box. Exports are written to `<documents>` and are
   not encrypted; delete them after copying them to a safe location.
2. **Copy the Hive directory.** With the application closed, copy every `*.hive` and `*.lock` file from
   `<documents>`, and the `hive_backups/` directory, to a safe location. Encrypted boxes are useful only
   together with the encryption key; do not clear secure storage or uninstall the application, which
   removes the key on most platforms.
3. **Do not use "Clear All Data".** Both variants enqueue delete tombstones that propagate to the
   backend (Section 7.10).
4. **Do not sign out on the capturing device** if the outbox may contain unsynchronized changes; sign-out
   purges authentication data, and the outbox cannot be pushed until a session exists again.
5. **Record the console output** of the failing launch and the telemetry file before restarting.

## 10. Reporting a Defect

When a failure is not covered here, open an issue titled `[Component] Brief description` and include:

- the application version from `pubspec.yaml` (currently `0.1.3+1`; the label in Settings is a fixed
  string that does not track this value), platform, operating system version and device model;
- the AI backend in use (Section 6.1) and whether a model file is present;
- the console output from launch to failure, with secrets, tokens and user identifiers removed;
- the relevant lines of `telemetry_events.jsonl`;
- for synchronization defects, the results of the queries in Section 2.4 with identifiers redacted;
- the exact reproduction steps, and the expected and observed behaviour.

Search the existing issues first: the audit findings are tracked as issues #2 to #66, and the summary
table in `audit/findings_report.md` maps each finding to its issue.
