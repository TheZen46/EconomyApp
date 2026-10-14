-- ============================================================================
-- Migration: 20260901_tenant_scoped_primary_keys.sql
-- Resolution for TAIDY-M02 / Issue #24:
-- Prevents cross-tenant primary key collisions (e.g. default box 'main' or
-- client-generated keys) in shared multi-tenant Supabase tables by making
-- primary keys tenant-scoped: PRIMARY KEY (user_id, id).
-- ============================================================================

-- 1. Financial Boxes
ALTER TABLE public.boxes DROP CONSTRAINT IF EXISTS boxes_pkey CASCADE;
ALTER TABLE public.boxes ADD PRIMARY KEY (user_id, id);

-- 2. Receipts
ALTER TABLE public.receipts DROP CONSTRAINT IF EXISTS receipts_pkey CASCADE;
ALTER TABLE public.receipts ADD PRIMARY KEY (user_id, id);

-- 3. Invoices
ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS invoices_pkey CASCADE;
ALTER TABLE public.invoices ADD PRIMARY KEY (user_id, id);

-- 4. Assets
ALTER TABLE public.assets DROP CONSTRAINT IF EXISTS assets_pkey CASCADE;
ALTER TABLE public.assets ADD PRIMARY KEY (user_id, id);

-- 5. Receipt Items
ALTER TABLE public.receipt_items DROP CONSTRAINT IF EXISTS receipt_items_pkey CASCADE;
ALTER TABLE public.receipt_items ADD PRIMARY KEY (user_id, id);

-- 6. Invoice Items
ALTER TABLE public.invoice_items DROP CONSTRAINT IF EXISTS invoice_items_pkey CASCADE;
ALTER TABLE public.invoice_items ADD PRIMARY KEY (user_id, id);
