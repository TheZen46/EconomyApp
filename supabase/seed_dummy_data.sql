-- ============================================================================
-- DUMMY DATA SEEDER FOR tAIdy (SUPABASE SQL EDITOR)
-- Generates and links realistic test data across all Dual-Tier tables
-- ============================================================================

-- Ensure color_hex is BIGINT to support full 32-bit ARGB hex numbers
ALTER TABLE public.boxes ALTER COLUMN color_hex TYPE BIGINT;

DO $$
DECLARE
    target_user_id UUID;
    new_box_id TEXT := 'box-' || gen_random_uuid()::text;
    new_receipt_id TEXT := 'rec-' || gen_random_uuid()::text;
    new_invoice_id TEXT := 'inv-' || gen_random_uuid()::text;
    new_asset_id TEXT := 'asset-' || gen_random_uuid()::text;
BEGIN
    -- 1. Grab the active user from auth.users
    SELECT id INTO target_user_id FROM auth.users ORDER BY created_at DESC LIMIT 1;
    
    IF target_user_id IS NULL THEN
        RAISE EXCEPTION 'No user found in auth.users. Please create or sign up a user in the app first.';
    END IF;

    RAISE NOTICE '===============================================================';
    RAISE NOTICE ' Seeding Dual-Tier Dummy Data for User: %', target_user_id;
    RAISE NOTICE '===============================================================';

    -- 2. Contextual Box (Tier 2 Vault)
    INSERT INTO public.boxes (
        id, user_id, name, budget, spent, currency, color_hex, icon_identifier, auto_categorize, keywords, is_private, version, created_at, updated_at
    ) VALUES (
        new_box_id, target_user_id, 'Hardware & Tech Gear', 5000.00, 3598.99, 'USD', 4278202791, 'Briefcase', true, 'Apple, Sony, Tech, Hardware', false, 1, now(), now()
    ) ON CONFLICT (id) DO UPDATE SET spent = EXCLUDED.spent, updated_at = now();

    -- 3. Core Financial Receipt (Tier 2 Vault)
    INSERT INTO public.receipts (
        id, user_id, merchant_name, total_amount, currency, scanned_date, image_path, vat_number, merchant_address, transaction_time, box_id, is_synced, version, created_at, updated_at
    ) VALUES (
        new_receipt_id, target_user_id, 'Apple Store - 5th Avenue (contact: apple.store@apple.com)', 3598.99, 'USD', now(), target_user_id || '/receipts/' || new_receipt_id || '.jpg', 'US-998877665', '767 5th Ave, New York, NY 10153', '15:30', new_box_id, true, 1, now(), now()
    ) ON CONFLICT (id) DO NOTHING;

    -- 4. Line Items (Triggers Tier 1 PII Scrubbing into receipt_training_labels)
    INSERT INTO public.receipt_items (
        id, receipt_id, user_id, description, quantity, unit_price, total_price, main_category, sub_category, necessity, is_asset, box_id, is_user_corrected, confidence_score, version, created_at, updated_at
    ) VALUES 
    (
        'item-' || gen_random_uuid()::text, new_receipt_id, target_user_id, 'MacBook Pro 16" M3 Max paid with Card 4532 0150 9988 1234', 1, 3499.00, 3499.00, 'Electronics', 'Computers & Laptops', 'essential', true, new_box_id, false, 0.9950, 1, now(), now()
    ),
    (
        'item-' || gen_random_uuid()::text, new_receipt_id, target_user_id, '140W USB-C Power Adapter & Braided Cable', 1, 99.99, 99.99, 'Electronics', 'Accessories & Chargers', 'essential', false, new_box_id, false, 0.9820, 1, now(), now()
    );

    -- 5. eVault Protected Asset (Tier 2 Vault)
    INSERT INTO public.vault_assets (
        id, user_id, receipt_id, name, merchant_name, purchase_date, warranty_months, price, receipt_image_path, document_path, version, created_at, updated_at
    ) VALUES (
        new_asset_id, target_user_id, new_receipt_id, 'MacBook Pro 16" M3 Max', 'Apple Store - 5th Avenue', now(), 36, 3499.00, target_user_id || '/images/' || new_receipt_id || '.jpg', target_user_id || '/documents/applecare_warranty.pdf', 1, now(), now()
    ) ON CONFLICT (id) DO NOTHING;

    -- 6. Business Invoice (Tier 2 Vault)
    INSERT INTO public.invoices (
        id, user_id, invoice_number, client_name, amount, currency, status, issued_date, due_date, notes, version, created_at, updated_at
    ) VALUES (
        new_invoice_id, target_user_id, 'INV-2026-888', 'Stripe Global Payments Inc.', 4850.00, 'USD', 'Sent', now(), now() + interval '30 days', 'Q3 Fintech Infrastructure Consultation & Smart Auditing', 1, now(), now()
    ) ON CONFLICT (id) DO NOTHING;

    -- 7. User Profile & Preferences
    INSERT INTO public.user_profiles (
        id, monthly_budget, default_currency, theme_mode, biometric_enabled, google_drive_sync_enabled, gamification_xp, gamification_streak, version, created_at, updated_at
    ) VALUES (
        target_user_id, 4500.00, 'USD', 'dark', true, false, 1850, 15, 2, now(), now()
    ) ON CONFLICT (id) DO UPDATE SET 
        monthly_budget = EXCLUDED.monthly_budget,
        gamification_xp = EXCLUDED.gamification_xp,
        gamification_streak = EXCLUDED.gamification_streak,
        version = public.user_profiles.version + 1,
        updated_at = now();

    RAISE NOTICE '✓ Box Created: "Hardware & Tech Gear" (ID: %)', new_box_id;
    RAISE NOTICE '✓ Receipt Created: "Apple Store - 5th Avenue" ($3598.99, ID: %)', new_receipt_id;
    RAISE NOTICE '✓ Invoice Created: #INV-2026-888 to Stripe Global Payments Inc. ($4850.00)';
    RAISE NOTICE '✓ eVault Asset Created: "MacBook Pro 16" M3 Max" (Warranty: 36 Months)';
    RAISE NOTICE '✓ User Profile Updated: Monthly Budget $4500, XP: 1850, Streak: 15 Days';
    RAISE NOTICE '===============================================================';
    RAISE NOTICE ' DUMMY DATA SEEDING COMPLETE! Check your Supabase Table Editor.';
    RAISE NOTICE '===============================================================';
END $$;
