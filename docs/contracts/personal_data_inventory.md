# Personal Data Inventory & Privacy Protection Contract

This document provides a comprehensive inventory of personal and financial data stored by tAIdy (EconomyApp), along with the cryptographic safeguards, redaction pipelines, and user consent controls enforcing data privacy.

## 1. Personal & Financial Data Inventory

| Data Category | Specific Data Elements | Storage Location | Protection Level |
| :--- | :--- | :--- | :--- |
| **Authentication & Identity** | Email address, Supabase User UUID | Local session storage & Supabase `auth.users` | Encrypted in OS Keychain / Keystore via `flutter_secure_storage` |
| **Biometric Credentials** | Fingerprint / Face ID enrollment state | Platform Secure Enclave | Never accessed or stored by tAIdy; delegated via `LocalAuthentication` |
| **Receipts & Transactions** | Merchant name, date, total amount, VAT ID, street address, line items | `receipts_v3` Hive box & Supabase `public.receipts` | AES-256 GCM encrypted at rest (`HiveAesCipher`) |
| **Receipt Images** | Physical receipt photos | Platform documents directory & Supabase Storage | Scoped to authenticated user ID with Supabase Row-Level Security |
| **Invoices & Receivables** | Client name, invoice number, amount, payment due date, notes | `invoices` Hive box & Supabase `public.invoices` | AES-256 GCM encrypted at rest (`HiveAesCipher`) |
| **EVault Asset Records** | Product name, purchase price, merchant, warranty proof photo | `assets` Hive box & Supabase `public.vault_assets` | AES-256 GCM encrypted at rest (`HiveAesCipher`) |
| **Banking Records** | Bank statement CSV imports, matched transactions, reconciliation logs | Ephemeral in-memory & `receipts_v3` box | Processed in-memory; persisted rows AES-256 encrypted |
| **AI Few-Shot Memory** | Corrected receipt line items and merchant subword embeddings | `<documents>/memory/episodic_memory.db` | SQLCipher encrypted SQLite database |
| **Application Telemetry** | Sanitized error types, inference latency, crash stack traces | `<documents>/logs/telemetry_events.jsonl` | Local JSONL; sanitized of PII, no remote transmission unless enabled |

---

## 2. Privacy Safeguards & Controls

### 2.1 PII Scrubber Pipeline (`PiiScrubberService`)

Before receipt metadata is stored in episodic memory or staged for dataset contributions, `PiiScrubberService` executes deterministic regex scrubbers to redact sensitive personal information:

- **Credit & Debit Cards**: 13 to 19 digit PAN sequences matching Luhn patterns (`[REDACTED_CARD]`).
- **Bank Account / IBAN Numbers**: International Bank Account Numbers (`[REDACTED_IBAN]`).
- **Social Security / Tax IDs**: US SSN (`XXX-XX-XXXX`) and European Codice Fiscale / Tax IDs (`[REDACTED_SSN]`).
- **Phone Numbers**: International and domestic phone formats (`[REDACTED_PHONE]`).
- **Email Addresses**: RFC 5322 email patterns (`[REDACTED_EMAIL]`).
- **Personal Names**: Cashier, server, customer, and personal honorific structures (`[REDACTED_NAME]`).
- **Street Addresses**: Structured street number and name combinations (`[REDACTED_ADDRESS]`).

### 2.2 Data Privacy Isolation Mode (`NetworkPolicy`)

When the user activates Isolation Mode in application settings (`isolation_mode_enabled = true`):
1. All outgoing cloud synchronization (`SyncManager`, `SyncService`) is blocked.
2. Remote AI inference (Google Gemini) is blocked; inference stays strictly on-device.
3. Training dataset contributions and Google Drive backups are suspended.
4. Over-the-air model updates and telemetry dispatches are halted.
5. All mutations remain queued in local encrypted Hive boxes until the user deactivates Isolation Mode.

### 2.3 Private Budget Envelopes (`BoxModel.isPrivate`)

Boxes flagged as `isPrivate: true` enforce privacy boundaries:
- Receipts assigned to private boxes are never staged into `dataset_contributions.jsonl`.
- Private box receipts are excluded from remote model fine-tuning candidate pools.

### 2.4 Secure Data Export & Purge

- **Temporary Exports**: When generating CSV or JSON exports, `ExportService` creates temporary files in restricted application storage and dispatches via the platform share sheet.
- **Data Purge**: Users can trigger `ReceiptListNotifier.clearAll(includeCloud: true)` to purge local Hive databases and execute remote cloud cascading deletes.
