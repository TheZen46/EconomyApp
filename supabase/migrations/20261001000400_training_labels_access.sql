-- Restricts the Tier-1 training corpus to the service role and stops the staging trigger from
-- rejecting receipt_items writes.
--
-- Before this migration:
-- - the SELECT policy on receipt_training_labels also admitted the "authenticated" role, so every
--   signed-in user could read every user's labels, including receipt_id values that link a label
--   to its owner's receipt;
-- - ai_training_dataset_v1 ran with its owner's privileges and was granted to anon and
--   authenticated by default, so it exposed the corpus without any RLS check, even to clients
--   holding only the public anon key;
-- - stage_anonymized_training_item() ran as the invoking user, and with no INSERT policy its
--   insert was rejected, which also rolled back the receipt_items write that fired it.
--
-- Verify with supabase/checks/training_labels_access.sql.

DROP POLICY IF EXISTS "Service role can view anonymized training labels" ON public.receipt_training_labels;
CREATE POLICY "Service role can view anonymized training labels"
ON public.receipt_training_labels FOR SELECT
USING (auth.jwt() ->> 'role' = 'service_role');

REVOKE ALL ON public.receipt_training_labels FROM anon, authenticated;

ALTER VIEW public.ai_training_dataset_v1 SET (security_invoker = true);
REVOKE ALL ON public.ai_training_dataset_v1 FROM anon, authenticated;

-- Runs as the function owner so that staging is independent of the caller's privileges; the
-- search_path is pinned because SECURITY DEFINER functions must not resolve names from the caller.
CREATE OR REPLACE FUNCTION public.stage_anonymized_training_item()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
$$;

-- Only the trigger may call it.
REVOKE ALL ON FUNCTION public.stage_anonymized_training_item() FROM PUBLIC, anon, authenticated;
