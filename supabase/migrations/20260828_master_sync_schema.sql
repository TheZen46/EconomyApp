-- ============================================================================
-- MASTER DATABASE & DUAL-TIER SYNCHRONIZATION SCHEMA (UNIVERSAL TYPE COMPATIBLE)
-- Project: tAIdy
-- ============================================================================

-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 2. Trigger Functions
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    NEW.version = COALESCE(OLD.version, 0) + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Clean up any legacy constraints that might cause type mismatch errors
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_schema = 'public' AND constraint_name = 'receipt_items_receipt_id_fkey'
    ) THEN
        ALTER TABLE public.receipt_items DROP CONSTRAINT receipt_items_receipt_id_fkey;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_schema = 'public' AND constraint_name = 'vault_assets_receipt_id_fkey'
    ) THEN
        ALTER TABLE public.vault_assets DROP CONSTRAINT vault_assets_receipt_id_fkey;
    END IF;
END $$;

-- ============================================================================
-- 3. Core Tables & Auto-Column Migration (TEXT IDs with Universal UUID Compatibility)
-- ============================================================================

-- 3.1 Receipts Table
CREATE TABLE IF NOT EXISTS public.receipts (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    merchant_name TEXT NOT NULL DEFAULT 'Unknown Merchant',
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    scanned_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    image_path TEXT,
    vat_number TEXT DEFAULT '',
    merchant_address TEXT DEFAULT '',
    transaction_time TEXT DEFAULT '',
    box_id TEXT DEFAULT 'main',
    is_synced BOOLEAN DEFAULT true,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS merchant_name TEXT NOT NULL DEFAULT 'Unknown Merchant';
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS currency VARCHAR(3) NOT NULL DEFAULT 'USD';
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS scanned_date TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS image_path TEXT;
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS vat_number TEXT DEFAULT '';
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS merchant_address TEXT DEFAULT '';
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS transaction_time TEXT DEFAULT '';
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS box_id TEXT DEFAULT 'main';
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS is_synced BOOLEAN DEFAULT true;
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_receipts_user_updated ON public.receipts(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_receipts_deleted_at ON public.receipts(deleted_at) WHERE deleted_at IS NOT NULL;

-- 3.2 Receipt Items Table
CREATE TABLE IF NOT EXISTS public.receipt_items (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    receipt_id TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    description TEXT NOT NULL DEFAULT 'Item',
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    main_category TEXT,
    sub_category TEXT,
    necessity TEXT NOT NULL DEFAULT 'unknown',
    is_asset BOOLEAN NOT NULL DEFAULT false,
    box_id TEXT DEFAULT 'main',
    is_user_corrected BOOLEAN NOT NULL DEFAULT false,
    confidence_score NUMERIC(5, 4) DEFAULT 1.0000,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS receipt_id TEXT;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT 'Item';
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS quantity INT NOT NULL DEFAULT 1;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS unit_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS total_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS main_category TEXT;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS sub_category TEXT;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS necessity TEXT NOT NULL DEFAULT 'unknown';
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS is_asset BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS box_id TEXT DEFAULT 'main';
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS is_user_corrected BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS confidence_score NUMERIC(5, 4) DEFAULT 1.0000;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Dynamically re-add foreign key if both columns are compatible (TEXT or UUID)
DO $$
BEGIN
    BEGIN
        ALTER TABLE public.receipt_items 
        ADD CONSTRAINT receipt_items_receipt_id_fkey 
        FOREIGN KEY (receipt_id) REFERENCES public.receipts(id) ON DELETE CASCADE;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Foreign key receipt_items -> receipts omitted due to legacy type difference; index maintained.';
    END;
END $$;

CREATE INDEX IF NOT EXISTS idx_receipt_items_receipt_id ON public.receipt_items(receipt_id);
CREATE INDEX IF NOT EXISTS idx_receipt_items_user_updated ON public.receipt_items(user_id, updated_at);

-- 3.3 Financial Boxes Table
CREATE TABLE IF NOT EXISTS public.boxes (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL DEFAULT 'Untitled Box',
    budget NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    spent NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    color_hex BIGINT NOT NULL DEFAULT 4278202791,
    icon_identifier TEXT,
    auto_categorize BOOLEAN NOT NULL DEFAULT false,
    keywords TEXT DEFAULT '',
    is_private BOOLEAN NOT NULL DEFAULT false,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS name TEXT NOT NULL DEFAULT 'Untitled Box';
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS budget NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS spent NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS currency VARCHAR(3) NOT NULL DEFAULT 'USD';
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS color_hex BIGINT NOT NULL DEFAULT 4278202791;
ALTER TABLE public.boxes ALTER COLUMN color_hex TYPE BIGINT;
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS icon_identifier TEXT;
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS auto_categorize BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS keywords TEXT DEFAULT '';
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.boxes ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_boxes_user_updated ON public.boxes(user_id, updated_at);

-- 3.4 Invoices Table
CREATE TABLE IF NOT EXISTS public.invoices (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    invoice_number TEXT NOT NULL DEFAULT 'INV-001',
    client_name TEXT NOT NULL DEFAULT 'Unknown Client',
    amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    status TEXT NOT NULL DEFAULT 'Draft',
    issued_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_date TIMESTAMPTZ,
    notes TEXT DEFAULT '',
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS invoice_number TEXT NOT NULL DEFAULT 'INV-001';
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS client_name TEXT NOT NULL DEFAULT 'Unknown Client';
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS currency VARCHAR(3) NOT NULL DEFAULT 'USD';
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'Draft';
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS issued_date TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS due_date TIMESTAMPTZ;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT '';
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_invoices_user_updated ON public.invoices(user_id, updated_at);

-- 3.5 eVault Protected Assets Table
CREATE TABLE IF NOT EXISTS public.vault_assets (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    receipt_id TEXT,
    name TEXT NOT NULL DEFAULT 'Protected Item',
    merchant_name TEXT DEFAULT '',
    purchase_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    warranty_months INT NOT NULL DEFAULT 12,
    price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    receipt_image_path TEXT DEFAULT '',
    document_path TEXT DEFAULT '',
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS receipt_id TEXT;
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS name TEXT NOT NULL DEFAULT 'Protected Item';
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS merchant_name TEXT DEFAULT '';
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS purchase_date TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS warranty_months INT NOT NULL DEFAULT 12;
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS price NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS receipt_image_path TEXT DEFAULT '';
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS document_path TEXT DEFAULT '';
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.vault_assets ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_vault_assets_user_updated ON public.vault_assets(user_id, updated_at);

-- 3.6 Taxonomies Table
CREATE TABLE IF NOT EXISTS public.taxonomies (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    hierarchy_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    overrides_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT unique_user_taxonomy UNIQUE (user_id)
);

ALTER TABLE public.taxonomies ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.taxonomies ADD COLUMN IF NOT EXISTS hierarchy_json JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.taxonomies ADD COLUMN IF NOT EXISTS overrides_json JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.taxonomies ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.taxonomies ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.taxonomies ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.taxonomies ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- 3.7 User Profiles Table
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    monthly_budget NUMERIC(12, 2) NOT NULL DEFAULT 2000.00,
    default_currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    theme_mode TEXT NOT NULL DEFAULT 'system',
    biometric_enabled BOOLEAN NOT NULL DEFAULT false,
    google_drive_sync_enabled BOOLEAN NOT NULL DEFAULT false,
    dashboard_layout JSONB DEFAULT '[]'::jsonb,
    gamification_xp INT NOT NULL DEFAULT 0,
    gamification_streak INT NOT NULL DEFAULT 0,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS monthly_budget NUMERIC(12, 2) NOT NULL DEFAULT 2000.00;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS default_currency VARCHAR(3) NOT NULL DEFAULT 'USD';
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS theme_mode TEXT NOT NULL DEFAULT 'system';
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS biometric_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS google_drive_sync_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS dashboard_layout JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS gamification_xp INT NOT NULL DEFAULT 0;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS gamification_streak INT NOT NULL DEFAULT 0;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- 3.8 Tier 1 Anonymized Receipt Training Labels Table
CREATE TABLE IF NOT EXISTS public.receipt_training_labels (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    receipt_id TEXT,
    anonymized_merchant TEXT NOT NULL DEFAULT 'Merchant',
    anonymized_description TEXT NOT NULL DEFAULT 'Item',
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    main_category TEXT,
    sub_category TEXT,
    necessity TEXT NOT NULL DEFAULT 'unknown',
    was_user_corrected BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_training_labels_category ON public.receipt_training_labels(main_category, sub_category);

-- ============================================================================
-- 4. PII Anonymization Functions & Triggers
-- ============================================================================

CREATE OR REPLACE FUNCTION public.anonymize_text(input_text TEXT)
RETURNS TEXT AS $$
DECLARE
    cleaned TEXT;
BEGIN
    IF input_text IS NULL THEN
        RETURN '';
    END IF;
    cleaned := input_text;
    cleaned := regexp_replace(cleaned, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', '[REDACTED_EMAIL]', 'g');
    cleaned := regexp_replace(cleaned, '\b(?:\d[ -]*?){13,19}\b', '[REDACTED_CARD]', 'g');
    cleaned := regexp_replace(cleaned, '(?:\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{3,4}', '[REDACTED_PHONE]', 'g');
    RETURN cleaned;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.stage_anonymized_training_item()
RETURNS TRIGGER AS $$
DECLARE
    rec_merchant TEXT;
BEGIN
    IF NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT merchant_name INTO rec_merchant FROM public.receipts WHERE id::text = NEW.receipt_id::text;
    rec_merchant := COALESCE(rec_merchant, 'Unknown Merchant');

    INSERT INTO public.receipt_training_labels (
        receipt_id,
        anonymized_merchant,
        anonymized_description,
        quantity,
        unit_price,
        total_price,
        main_category,
        sub_category,
        necessity,
        was_user_corrected,
        created_at
    ) VALUES (
        NEW.receipt_id::text,
        public.anonymize_text(rec_merchant),
        public.anonymize_text(NEW.description),
        NEW.quantity,
        NEW.unit_price,
        NEW.total_price,
        NEW.main_category,
        NEW.sub_category,
        NEW.necessity,
        NEW.is_user_corrected,
        now()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_stage_training_item ON public.receipt_items;
CREATE TRIGGER trg_stage_training_item
AFTER INSERT OR UPDATE ON public.receipt_items
FOR EACH ROW EXECUTE FUNCTION public.stage_anonymized_training_item();

-- 4.1 Secure View for AI Model Training Export (Tier 1 View)
CREATE OR REPLACE VIEW public.ai_training_dataset_v1 AS
SELECT
    id AS sample_id,
    anonymized_merchant AS merchant,
    anonymized_description AS item_text,
    quantity,
    unit_price,
    total_price,
    main_category,
    sub_category,
    necessity,
    was_user_corrected,
    created_at AS recorded_at
FROM public.receipt_training_labels
WHERE anonymized_description IS NOT NULL AND length(anonymized_description) > 1;

-- ============================================================================
-- 5. Attach Updated-At Triggers to All Tables
-- ============================================================================
DROP TRIGGER IF EXISTS trg_receipts_updated_at ON public.receipts;
CREATE TRIGGER trg_receipts_updated_at BEFORE UPDATE ON public.receipts
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_receipt_items_updated_at ON public.receipt_items;
CREATE TRIGGER trg_receipt_items_updated_at BEFORE UPDATE ON public.receipt_items
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_boxes_updated_at ON public.boxes;
CREATE TRIGGER trg_boxes_updated_at BEFORE UPDATE ON public.boxes
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_invoices_updated_at ON public.invoices;
CREATE TRIGGER trg_invoices_updated_at BEFORE UPDATE ON public.invoices
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_vault_assets_updated_at ON public.vault_assets;
CREATE TRIGGER trg_vault_assets_updated_at BEFORE UPDATE ON public.vault_assets
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_taxonomies_updated_at ON public.taxonomies;
CREATE TRIGGER trg_taxonomies_updated_at BEFORE UPDATE ON public.taxonomies
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_user_profiles_updated_at ON public.user_profiles;
CREATE TRIGGER trg_user_profiles_updated_at BEFORE UPDATE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 6. Row Level Security (RLS) Policies (Clean Drop & Recreate)
-- ============================================================================

ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.boxes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vault_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_training_labels ENABLE ROW LEVEL SECURITY;

-- 6.1 Receipts RLS
DROP POLICY IF EXISTS "Users can manage their own receipts" ON public.receipts;
CREATE POLICY "Users can manage their own receipts"
ON public.receipts FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 6.2 Receipt Items RLS
DROP POLICY IF EXISTS "Users can manage their own receipt items" ON public.receipt_items;
CREATE POLICY "Users can manage their own receipt items"
ON public.receipt_items FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 6.3 Boxes RLS
DROP POLICY IF EXISTS "Users can manage their own boxes" ON public.boxes;
CREATE POLICY "Users can manage their own boxes"
ON public.boxes FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 6.4 Invoices RLS
DROP POLICY IF EXISTS "Users can manage their own invoices" ON public.invoices;
CREATE POLICY "Users can manage their own invoices"
ON public.invoices FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 6.5 Vault Assets RLS
DROP POLICY IF EXISTS "Users can manage their own vault assets" ON public.vault_assets;
CREATE POLICY "Users can manage their own vault assets"
ON public.vault_assets FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 6.6 Taxonomies RLS
DROP POLICY IF EXISTS "Users can manage their own taxonomy config" ON public.taxonomies;
CREATE POLICY "Users can manage their own taxonomy config"
ON public.taxonomies FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 6.7 User Profiles RLS
DROP POLICY IF EXISTS "Users can manage their own profile" ON public.user_profiles;
CREATE POLICY "Users can manage their own profile"
ON public.user_profiles FOR ALL
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- 6.8 Training Labels RLS
DROP POLICY IF EXISTS "Service role can view anonymized training labels" ON public.receipt_training_labels;
CREATE POLICY "Service role can view anonymized training labels"
ON public.receipt_training_labels FOR SELECT
USING (auth.jwt() ->> 'role' = 'service_role' OR auth.jwt() ->> 'role' = 'authenticated');

-- ============================================================================
-- 7. Storage Buckets & Isolation Policies
-- ============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('receipt_images', 'receipt_images', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('asset_documents', 'asset_documents', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('training_data', 'training_data', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Users can manage their own receipt images" ON storage.objects;
CREATE POLICY "Users can manage their own receipt images"
ON storage.objects FOR ALL
USING (bucket_id = 'receipt_images' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'receipt_images' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Users can manage their own asset documents" ON storage.objects;
CREATE POLICY "Users can manage their own asset documents"
ON storage.objects FOR ALL
USING (bucket_id = 'asset_documents' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'asset_documents' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Users can manage training_data folder" ON storage.objects;
CREATE POLICY "Users can manage training_data folder"
ON storage.objects FOR ALL
USING (bucket_id = 'training_data' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'training_data' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Service role can read receipt images for training" ON storage.objects;
CREATE POLICY "Service role can read receipt images for training"
ON storage.objects FOR SELECT
USING (bucket_id IN ('receipt_images', 'training_data') AND auth.jwt() ->> 'role' = 'service_role');
