-- Access checks for the Tier-1 training corpus (receipt_training_labels and
-- ai_training_dataset_v1).
--
-- Asserts that end users and anonymous clients cannot read the corpus, that
-- writes to receipt_items are not rejected by the staging trigger, and that the
-- service role can read what was staged. Runs inside a transaction that is
-- rolled back, so it leaves no data behind.
--
-- Run as a superuser against a database with all migrations applied, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/checks/training_labels_access.sql
-- Any failed assertion aborts with an error naming the violated property.

BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-4000-8000-00000000000a'),
  ('00000000-0000-4000-8000-00000000000b');

-- User A saves a receipt with one line item.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';

INSERT INTO public.receipts (id, user_id, merchant_name, total_amount)
VALUES ('check-receipt-a', '00000000-0000-4000-8000-00000000000a', 'Bakery', 4.50);

DO $$
BEGIN
  INSERT INTO public.receipt_items (receipt_id, user_id, description, unit_price, total_price)
  VALUES ('check-receipt-a', '00000000-0000-4000-8000-00000000000a', 'Bread', 4.50, 4.50);
EXCEPTION WHEN insufficient_privilege THEN
  RAISE EXCEPTION 'receipt_items write was rejected by the training-label trigger';
END $$;

-- User B and anonymous clients must not be able to read the corpus.
SET LOCAL request.jwt.claims TO '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';

DO $$
DECLARE visible int;
BEGIN
  BEGIN
    SELECT count(*) INTO visible FROM public.receipt_training_labels;
  EXCEPTION WHEN insufficient_privilege THEN visible := 0;
  END;
  IF visible > 0 THEN
    RAISE EXCEPTION 'authenticated users can read % row(s) of receipt_training_labels', visible;
  END IF;

  BEGIN
    SELECT count(*) INTO visible FROM public.ai_training_dataset_v1;
  EXCEPTION WHEN insufficient_privilege THEN visible := 0;
  END;
  IF visible > 0 THEN
    RAISE EXCEPTION 'authenticated users can read % row(s) of ai_training_dataset_v1', visible;
  END IF;
END $$;

RESET ROLE;
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims TO '{"role": "anon"}';

DO $$
DECLARE visible int;
BEGIN
  BEGIN
    SELECT count(*) INTO visible FROM public.ai_training_dataset_v1;
  EXCEPTION WHEN insufficient_privilege THEN visible := 0;
  END;
  IF visible > 0 THEN
    RAISE EXCEPTION 'anonymous clients can read % row(s) of ai_training_dataset_v1', visible;
  END IF;
END $$;

-- The training pipeline (service role) sees the staged label.
RESET ROLE;
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims TO '{"role": "service_role"}';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.receipt_training_labels WHERE receipt_id = 'check-receipt-a') THEN
    RAISE EXCEPTION 'the service role cannot read the staged training label';
  END IF;
END $$;

RESET ROLE;
ROLLBACK;
