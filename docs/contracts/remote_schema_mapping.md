# Remote Database Schema Mapping Contract

This document specifies the bidirectional serialization mapping between local Dart data transfer objects (DTOs) and remote Supabase PostgreSQL schema tables.

## 1. Table & Entity Mapping Matrix

| Entity Type | Dart Model Class | Remote Supabase Table | Primary Key |
| :--- | :--- | :--- | :--- |
| `receipt` | `ReceiptModel` | `public.receipts` | `id` (UUID v4 / TEXT) |
| `receipt_item` | `ReceiptItemModel` | `public.receipt_items` (or embedded JSONB in `receipts.items`) | `id` (TEXT) |
| `box` | `BoxModel` | `public.boxes` | `id` (UUID v4 / TEXT) |
| `invoice` | `InvoiceModel` | `public.invoices` | `id` (UUID v4 / TEXT) |
| `asset` | `AssetModel` | `public.vault_assets` | `id` (UUID v4 / TEXT) |
| `profile` | `UserProfileModel` | `public.user_profiles` | `id` (UUID v4 / TEXT) |

---

## 2. Detailed Field Specifications

### 2.1 Receipts (`public.receipts` <-> `ReceiptModel`)

| SQL Column | SQL Type | Dart Property | Dart Type | Nullable | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `id` | `String` | No | UUID v4 formatted string |
| `user_id` | `UUID` | `userId` | `String?` | Yes | RLS owner foreign key |
| `merchant_name` | `TEXT` | `merchantName` | `String` | No | Defaults to `'Unknown Merchant'` |
| `total_amount` | `NUMERIC(12,2)` | `totalAmount` | `double` | No | Standard currency scale |
| `currency` | `VARCHAR(3)` | `currency` | `String` | No | ISO 4217 code (e.g. `USD`, `EUR`) |
| `scanned_date` | `TIMESTAMPTZ` | `date` | `DateTime` | No | Timestamp of the transaction |
| `image_path` | `TEXT` | `imagePath` | `String?` | Yes | Storage path or local URI |
| `vat_number` | `TEXT` | `vatNumber` | `String?` | Yes | Tax identifier |
| `merchant_address` | `TEXT` | `merchantAddress` | `String?` | Yes | Redacted merchant street address |
| `transaction_time` | `TEXT` | `transactionTime` | `String?` | Yes | Extracted time string (`HH:mm:ss`) |
| `box_id` | `TEXT` | `boxId` | `String?` | Yes | Assigned envelope box ID |
| `items` | `JSONB` | `items` | `List<ReceiptItemModel>` | Yes | Serialized line items array |
| `version` | `INT` | `version` | `int` | No | Monotonic CRDT version counter |
| `created_at` | `TIMESTAMPTZ` | `createdAt` | `DateTime?` | Yes | Record creation UTC timestamp |
| `updated_at` | `TIMESTAMPTZ` | `updatedAt` | `DateTime?` | Yes | Last update UTC timestamp |
| `deleted_at` | `TIMESTAMPTZ` | `deletedAt` | `DateTime?` | Yes | Soft-delete tombstone timestamp |

### 2.2 Budget Boxes (`public.boxes` <-> `BoxModel`)

| SQL Column | SQL Type | Dart Property | Dart Type | Nullable | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `id` | `String` | No | Unique ID (`main` or UUID v4) |
| `user_id` | `UUID` | `userId` | `String?` | Yes | RLS owner foreign key |
| `name` | `TEXT` | `name` | `String` | No | Box title |
| `budget` | `NUMERIC(12,2)` | `budget` | `double` | No | Monthly ceiling |
| `spent` | `NUMERIC(12,2)` | `spent` | `double` | No | Running monthly spent total |
| `currency` | `VARCHAR(3)` | `currency` | `String` | No | ISO 4217 currency code |
| `color` | `INT` | `color` | `int` | Yes | 32-bit ARGB color value |
| `icon` | `TEXT` | `icon` | `String?` | Yes | Icon identifier |
| `is_private` | `BOOLEAN` | `isPrivate` | `bool` | Yes | True excludes from AI training |
| `auto_categorize` | `BOOLEAN` | `autoCategorize` | `bool` | Yes | Automatic keyword allocation flag |
| `keywords` | `TEXT` | `keywords` | `String` | Yes | Comma-separated keyword rules |
| `version` | `INT` | `version` | `int` | No | Monotonic version counter |
| `created_at` | `TIMESTAMPTZ` | `createdAt` | `DateTime?` | Yes | Creation UTC timestamp |
| `updated_at` | `TIMESTAMPTZ` | `updatedAt` | `DateTime?` | Yes | Last update UTC timestamp |
| `deleted_at` | `TIMESTAMPTZ` | `deletedAt` | `DateTime?` | Yes | Soft-delete tombstone timestamp |

### 2.3 Invoices (`public.invoices` <-> `InvoiceModel`)

| SQL Column | SQL Type | Dart Property | Dart Type | Nullable | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `id` | `String` | No | UUID v4 string |
| `user_id` | `UUID` | `userId` | `String?` | Yes | RLS owner foreign key |
| `invoice_number` | `TEXT` | `invoiceNumber` | `String` | No | Unique sequence code |
| `client_name` | `TEXT` | `clientName` | `String` | No | Billed customer/company |
| `amount` | `NUMERIC(12,2)` | `amount` | `double` | No | Total billed value |
| `status` | `TEXT` | `status` | `String` | No | Status (`draft`, `sent`, `settled`, `overdue`) |
| `issued_date` | `TIMESTAMPTZ` | `issuedDate` | `DateTime` | No | Issuance timestamp |
| `due_date` | `TIMESTAMPTZ` | `dueDate` | `DateTime?` | Yes | Payment deadline timestamp |
| `notes` | `TEXT` | `notes` | `String` | Yes | Client or remittance notes |
| `currency` | `VARCHAR(3)` | `currency` | `String` | No | Currency code |
| `version` | `INT` | `version` | `int` | No | Monotonic version counter |
| `created_at` | `TIMESTAMPTZ` | `createdAt` | `DateTime?` | Yes | Creation UTC timestamp |
| `updated_at` | `TIMESTAMPTZ` | `updatedAt` | `DateTime?` | Yes | Last update UTC timestamp |
| `deleted_at` | `TIMESTAMPTZ` | `deletedAt` | `DateTime?` | Yes | Soft-delete tombstone timestamp |

### 2.4 Protected Assets (`public.vault_assets` <-> `AssetModel`)

| SQL Column | SQL Type | Dart Property | Dart Type | Nullable | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `id` | `String` | No | UUID v4 string |
| `user_id` | `UUID` | `userId` | `String?` | Yes | RLS owner foreign key |
| `name` | `TEXT` | `name` | `String` | No | Asset description |
| `purchase_date` | `TIMESTAMPTZ` | `purchaseDate` | `DateTime` | No | Purchase timestamp |
| `warranty_months`| `INT` | `warrantyMonths` | `int` | No | Warranty duration in months |
| `price` | `NUMERIC(12,2)` | `price` | `double` | No | Valuation or cost |
| `receipt_image_path` | `TEXT` | `receiptImagePath` | `String` | Yes | Path to receipt proof image |
| `merchant_name` | `TEXT` | `merchantName` | `String?` | Yes | Seller name |
| `receipt_id` | `TEXT` | `receiptId` | `String?` | Yes | Linked receipt identifier |
| `version` | `INT` | `version` | `int` | No | Monotonic version counter |
| `created_at` | `TIMESTAMPTZ` | `createdAt` | `DateTime?` | Yes | Creation UTC timestamp |
| `updated_at` | `TIMESTAMPTZ` | `updatedAt` | `DateTime?` | Yes | Last update UTC timestamp |
| `deleted_at` | `TIMESTAMPTZ` | `deletedAt` | `DateTime?` | Yes | Soft-delete tombstone timestamp |
