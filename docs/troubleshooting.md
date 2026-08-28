# 🛠️ The "Symptom-Resolution" Protocol (Troubleshooting)

When encountering structural blocks, dependencies issues, or AI-execution bottlenecks within EconomyApp (tAIdy), developers should reference the diagnostic tree and S.C.R.V resolutions established below.

```mermaid
graph TD
    A[Error Encountered] --> B{Error Type?}
    
    B -- Web Compilation --> C[Check dart:ffi Usage]
    C --> D[Review Conditional Exports]
    D --> E[Resolved]
    
    B -- Secret Reject --> F[Check commit history]
    F --> G[Clear BFG Repo-Cleaner / Reset]
    G --> E
    
    B -- Webhook Latency --> H[Check Network Header]
    H --> I[Validate X-Auth-Secret]
    I --> E
```

---

#### **[Web Compilation FFI Crash]**

**Symptom:**
*When executing `flutter build web` to generate standard web pages or trigger GitHub Actions, the compiler crashes almost immediately, throwing errors similar to:*
> `Error: 'Pointer' isn't a type.` referencing `llama_cpp_dart/llama_cpp_dart.dart`.

**Root Cause:**
The `llama_cpp_dart` package uses `dart:ffi` directly to invoke native C++ binaries for executing the mathematical Large Language Models constraints. However, `dart:ffi` is explicitly isolated and unsupported within the JS/Wasm constraints of standard Flutter Web compilations. Reaching out to an unconditional `import package:llama` inside a file evaluated by the web compiler terminates the node process entirely.

**Resolution:**
*Enforce conditional abstract bindings so the Wasm compiler cannot parse the FFI logic.*
1. Locate the native execution service `lib/core/services/llm_service.dart`.
2. Extract the actual local C++ imports into a new file `llm_service_mobile.dart`.
3. Extract an empty "hollow" interface representing the endpoints into `llm_service_stub.dart`.
4. Wrap the root `llm_service.dart` with conditional compilation bounds to seamlessly proxy requests depending on the platform:
```dart
export 'llm_service_stub.dart'
  if (dart.library.io) 'llm_service_mobile.dart';
```
5. Clear caches and reboot the toolchain via your terminal: `flutter clean && flutter build web`

**Verification:**
*The web compiler will cleanly navigate past the AI layer logic. The terminal will successfully output:*
> `Wasm dry run succeeded`
> `Built build\web`

---

#### **[Git Push Push Protection Block]**

**Symptom:**
*When pushing standard updates using `git push origin main`, the terminal stops the transaction and drops the connection with:*
> `remote: error: GH013: Repository rule violations found for refs/heads/main.`
> `! [remote rejected] main -> main (push declined due to repository rule violations)`

**Root Cause:**
GitHub's built in "Secret Scanning" mechanism detected that a file tracked by git (likely `assets/credentials.json` or `pubspec.yaml`) contains active Google Gemini API Tokens or Supabase Auth Secrets.

**Resolution:**
1. Discard the current `.git` mapping to drop the local trace. Alternatively use `git reset --soft` specifically to the parent.
2. In the project root, edit the `.gitignore` safely bypassing tracking the credentials file:
   ```bash
   echo "assets/credentials.json" >> .gitignore
   ```
3. Commit cleanly:
   ```bash
   git add . && git commit -m "Chore: Initialize properly without exposed configurations"
   ```
4. Push forcibly to rewrite the branch tree:
   ```bash
   git push -u origin main -f
   ```

**Verification:**
*The terminal will bypass the security checkpoint and register the tree updates:*
> `* [new branch] main -> main`

---

#### **[Supabase Storage RLS 403 / Unauthorized Upload]**

**Symptom:**
*When synchronizing local receipts with Supabase Storage, the console reports:*
> `Supabase upload failed: StorageException(message: new row violates row-level security policy, statusCode: 403, error: Unauthorized)`

**Root Cause:**
The `receipts` storage bucket has Row-Level Security (RLS) enabled, but lacks an `INSERT`/`SELECT` policy permitting authenticated users to write to their isolated path prefix (`training_data/<userId>/` or `<userId>/`).

**Resolution:**
Execute the following SQL in your Supabase SQL Editor to grant authenticated users access to their user directory:
```sql
CREATE POLICY "Allow authenticated user folder access"
ON storage.objects
FOR ALL
TO authenticated
USING (bucket_id = 'receipts' AND (auth.uid()::text = (storage.foldername(name))[2] OR auth.uid()::text = (storage.foldername(name))[1]))
WITH CHECK (bucket_id = 'receipts' AND (auth.uid()::text = (storage.foldername(name))[2] OR auth.uid()::text = (storage.foldername(name))[1]));
```

---

#### **[Postgrest PGRST204 Schema Cache Notice]**

**Symptom:**
*During receipt synchronization, the terminal logs:*
> `Supabase database receipts table upsert notice: PostgrestException(message: Could not find the 'image_path' column of 'receipts' in the schema cache, code: PGRST204)`

**Root Cause:**
The remote PostgreSQL `receipts` table does not yet have the `image_path` column defined, or PostgREST's schema cache has not reloaded.

**Resolution:**
1. `SyncService` is built to gracefully capture this notice and proceed without interrupting receipt syncing.
2. To link image paths permanently in PostgreSQL, execute:
```sql
ALTER TABLE receipts ADD COLUMN IF NOT EXISTS image_path TEXT;
NOTIFY pgrst, 'reload schema';
```

---

#### **[Sync Interruption & Network Drop]**

**Symptom:**
*The kinetic replication bar displays `Retrying in X.Xs` or stays on `Stage: interruptedRetrying`.*

**Root Cause:**
Transient network loss or cellular signal drop during delta binary asset downloads.

**Resolution:**
1. **Auto-Recovery**: `SyncEngine` listens to `connectivity_plus` and will automatically resume once internet connectivity returns.
2. **Offline Fallback**: Tap **Continue in Offline Mode** on the bottom of `/sync_progress` to immediately enter the dashboard with existing local caches.
3. **Manual Retry**: In **Settings** $\rightarrow$ **Sync Center**, tap **Replicate Cloud Data** once network stability is restored.

