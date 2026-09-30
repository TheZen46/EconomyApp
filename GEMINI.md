# tAIdy Codebase & Architectural Invariants

## 1. UI/UX Design System & Aesthetics (Cyberpunk Financial HUD)
- **Typography:**
  - Standard UI labels, headers, and body: `GoogleFonts.spaceGrotesk(...)`.
  - Financial amounts, dates, timestamps, counters, codes, telemetry: `GoogleFonts.jetBrainsMono(...)`.
- **Color Discipline:**
  - Never hardcode raw hex values in presentation widgets. Use `Theme.of(context).colorScheme` or semantic `AppColors` tokens.
  - Primary Accent: Klein Blue (`AppColors.accent` / `#002FA7`).
  - Dark Surface: Obsidian Black (`#0A0A0A` / `#0D0D11`).
  - Telemetry / Status: Emerald (`#10B981` / `#4ADE80`), Neon Cyan (`#0891B2`), Amber (`#F59E0B`), Crimson (`#D4183D`).
- **Responsive Flex & Layouts:**
  - Wrap chips, badges, and horizontal tags in `Wrap` or `FittedBox` to prevent `RenderFlex` overflows on small displays (320px) and desktop layouts.
- **State Feedback:**
  - Never unmount whole dashboard screens to show full-page loading spinners for routine CRUD. Use optimistic UI mutations (`state = AsyncValue.data(updatedList)`).

## 2. Dual-Tier Privacy & AI Training Governance
- **Tier 1 (AI Training Ground Truth):**
  - Receipts, item descriptions, prices, quantities, taxonomy mappings, necessity tags (`essential`, `discretional`, `junk`), and user corrections.
  - Automatically strip personal PII (user emails, card numbers, personal addresses) before aggregating into developer-accessible training views.
- **Tier 2 (Strict User Vault):**
  - Invoices, client names/terms, eVault asset warranties, custom private boxes, bank CSV raw records, and API credentials.
  - Enforce strict Row-Level Security (RLS) in Supabase: `auth.uid() = user_id`.

## 3. Storage, Concurrency & State Invariants
- **Monotonic Counters:** Never derive sequential numbers (e.g. invoice IDs) from list lengths. Persist monotonic counters in Hive boxes.
- **Synchronous Mutex Locks:** In sync/queue processors, set `_isSyncing = true` synchronously before any `await` calls, and release inside `finally`.
- **Date & Calendar Arithmetic:** Always use calendar-aware addition `DateTime(year, month + duration, day, ...)` rather than assuming 30-day months.
- **Safe Test Provider Fallbacks:** When exposing Hive-backed or platform-dependent providers, provide safe non-throwing fallbacks (e.g. `ThemeNotifier(null)`) so standalone widget tests run cleanly without crashes.
