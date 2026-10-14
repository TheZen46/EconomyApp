# Hive Operational Contracts & Type Registry

This document defines the authoritative registry for Hive type identifiers (`typeId`), box names, and settings key ownership for tAIdy (EconomyApp).

## 1. Hive Type Identifier (`typeId`) Registry

Hive requires each registered type adapter to have a unique integer identifier within the range 0 to 223. Once assigned and persisted in users' local `.hive` files, a `typeId` **must never be changed, reassigned, or deleted**, as doing so breaks backward compatibility and causes fatal deserialization errors.

| typeId | Dart Type | Model File | Adapter Class | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0` | `ReceiptModel` | `lib/features/receipt_scanning/data/models/receipt_model.dart` | `ReceiptModelAdapter` | Root receipt entity with metadata and embedded line items |
| `1` | `ReceiptItemModel` | `lib/features/receipt_scanning/data/models/receipt_model.dart` | `ReceiptItemModelAdapter` | Individual receipt line item |
| `2` | `DashboardWidgetType` | `lib/features/receipt_scanning/data/models/dashboard_config.dart` | `DashboardWidgetTypeAdapter` | Enum for customizable dashboard cards |
| `3` | `DashboardItem` | `lib/features/receipt_scanning/data/models/dashboard_config.dart` | `DashboardItemAdapter` | Positioned dashboard widget state |
| `4` | `TaxonomyItemModel` | `lib/features/settings/data/models/taxonomy_model.dart` | `TaxonomyItemModelAdapter` | Expense category taxonomy item |
| `5` | `TaxonomyConfigModel` | `lib/features/settings/data/models/taxonomy_model.dart` | `TaxonomyConfigModelAdapter` | Configured hierarchy of categories |
| `6` | `SyncItemModel` | `lib/features/receipt_scanning/data/models/sync_item_model.dart` | `SyncItemModelAdapter` | Legacy receipt upload queue item |
| `7` | `AssetModel` | `lib/features/evault/data/models/asset_model.dart` | `AssetModelAdapter` | Warrantied physical inventory item |
| `10` | `BoxModel` | `lib/features/boxes/data/models/box_model.dart` | `BoxModelAdapter` | Budget envelope context |
| `11` | `InvoiceModel` | `lib/features/invoices/data/models/invoice_model.dart` | `InvoiceModelAdapter` | Invoicing and accounts receivable record |
| `12` | `SyncOutboxItem` | `lib/core/sync/models/sync_outbox_item.dart` | `SyncOutboxItemAdapter` | Offline CRDT mutation queue item |
| `13` | `UserProfileModel` | `lib/features/settings/data/models/user_profile_model.dart` | `UserProfileModelAdapter` | Encrypted user profile and KYC metadata |

*Reserved IDs*:
- `8`, `9`: Reserved for future transaction and tax profile extensions.

---

## 2. Hive Box Registry

All boxes holding user financial data or sensitive configuration are encrypted at rest with AES-256 ciphers (`HiveAesCipher`) derived from the OS keychain via `SecureStorageService`.

| Box Name | Generic Value Type | Cipher | Opened In | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `settings` | `dynamic` | `HiveAesCipher` | `lib/main.dart` | Application preferences, counters, flags, sync watermarks |
| `taxonomy_config` | `TaxonomyConfigModel` | `HiveAesCipher` | `lib/main.dart` | Custom expense category taxonomies |
| `receipts_v3` | `ReceiptModel` | `HiveAesCipher` | `lib/main.dart` | Scanned and imported receipts |
| `sync_queue` | `SyncItemModel` | `HiveAesCipher` | `lib/main.dart` | Legacy attachment upload queue |
| `assets` | `AssetModel` | `HiveAesCipher` | `lib/main.dart` | EVault protected inventory items |
| `boxes` | `BoxModel` | `HiveAesCipher` | `lib/main.dart` | Budget segregation boxes |
| `invoices` | `InvoiceModel` | `HiveAesCipher` | `lib/main.dart` | Accounts receivable invoices |
| `sync_outbox` | `SyncOutboxItem` | `HiveAesCipher` | `lib/main.dart` | Offline-first sync mutation queue |

---

## 3. Settings Key Ownership Contract

The `settings` box stores unstructured key-value records. To avoid naming collisions across features, keys are strictly owned by specific producers:

| Key | Value Type | Owner / Producer | Semantics & Purpose |
| :--- | :--- | :--- | :--- |
| `schema_version` | `int` | `HiveMigrationService` | Monotonic schema migration counter (current: `3`) |
| `theme_mode` | `String` (`'light'` \| `'dark'` \| `'system'`) | `ThemeNotifier` | Active UI theme mode preference |
| `monthly_budget_limit` | `double` | `BudgetNotifier` | Monthly discretionary spending ceiling |
| `current_balance` | `double` | `CurrentBalanceNotifier` | User's primary cash or bank balance |
| `projected_income` | `double` | `ProjectedIncomeNotifier` | Expected monthly incoming cash flow |
| `privacy_mode_enabled` | `bool` | `PrivacyModeNotifier` | Masks monetary amounts in presentation UI |
| `tax_nest_rate` | `double` | `TaxNestRateNotifier` | Marginal tax withholding fraction (e.g. `0.25`) |
| `tax_nest_goal` | `double` | `TaxNestGoalNotifier` | Statutory tax reserve target balance |
| `global_invoice_counter` | `int` | `InvoicesNotifier` | Monotonic fallback invoice sequence index |
| `invoice_device_partition` | `String` | `InvoicesNotifier` | Optional per-device prefix for invoice collision prevention |
| `sync_watermark_*` | `String` (ISO 8601) | `SyncManager` | High-water mark timestamp for delta pull queries |
| `enable_gemini_ai` | `bool` | Settings UI | Opt-in toggle for Google Gemini cloud extraction |
| `isolation_mode_enabled` | `bool` | `NetworkPolicy` | Privacy toggle disabling all external network calls |
