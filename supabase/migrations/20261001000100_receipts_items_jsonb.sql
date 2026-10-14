-- Stores receipt line items on the receipt row as a JSON array.
--
-- The client serializes each receipt with an embedded `items` array (ReceiptModel.toRemoteJson)
-- and both pull paths (SyncManager and SyncEngine) read it from the row. Without this column
-- PostgREST rejects every receipt upsert with PGRST204.
--
-- NULL means that the row carries no item information (rows written before this migration);
-- clients keep their local items in that case.
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS items JSONB;

-- Make the new column visible to PostgREST without waiting for its periodic schema reload.
NOTIFY pgrst, 'reload schema';
