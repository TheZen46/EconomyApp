# Project: tAIdy (EconomyApp)

## Architecture
- Flutter Application targeting desktop, web, and mobile (Android & iOS).
- Riverpod state management, encrypted Hive NoSQL local persistence, Supabase cloud synchronization.
- Edge AI inference (`llama.cpp`) with cloud fallback (`google_generative_ai`).
- International Klein Blue (IKB) design system with Space Grotesk & JetBrains Mono typography.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | UI & Design System Overhaul | Figma IKB design system, kinetic animations, responsive grid layouts | none | COMPLETED |
| 2 | Activity Contexts (Boxes) | Contextual spending envelopes, dynamic velocity charts, budget pacing | Riverpod, Hive | COMPLETED |
| 3 | Invoice Management | Billed invoices tracker, status lifecycle, revenue velocity metrics | Riverpod, Hive | COMPLETED |
| 4 | Digital Vault (eVault) | Warranty tracking, protected asset inventory, evidentiary image linking | Riverpod, Hive | COMPLETED |
| 5 | AI Receipt Ingestion | Optical character recognition, LLM multi-tier parsing, downscaled memory optimization | ML Kit, Gemini | COMPLETED |
| 6 | Cross-Device Sync Engine | Bit-for-bit file replication, delta syncing, kinetic progress UI, post-login router guard | Supabase, GoRouter | COMPLETED |

## Interface Contracts
- `/v1/webhooks/receipts` — Webhook ingestion endpoint.
- `training_data/<userId>/` — Supabase Storage binary replication contract.
- Supabase PostgreSQL sync tables: `receipts`, `boxes`, `assets`, `invoices`, `taxonomies`.

## Code Layout
- `lib/main.dart` — entry point & bootstrap pipeline
- `lib/core/` — router (`app_router.dart`), security, storage, theme, failure models
- `lib/features/sync/` — cross-device sync engine, remote replica data source, kinetic visualizer
- `lib/features/receipt_scanning/` — receipt ingestion, dashboard widgets, review page
- `lib/features/boxes/` — activity contexts and box creator
- `lib/features/invoices/` — invoice tracking and revenue charts
- `lib/features/evault/` — digital warranty vault and protected asset catalog
- `lib/features/settings/` — app preferences, sync center, LLM manager
- `lib/features/auth/` — Supabase authentication, biometric guard, reactive router notifier
