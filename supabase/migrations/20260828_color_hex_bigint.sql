-- Add BIGINT migration for color_hex in schema.sql
ALTER TABLE public.boxes ALTER COLUMN color_hex TYPE BIGINT;
