-- Fixes card-number redaction in public.anonymize_text().
--
-- The previous pattern used \b, which PostgreSQL regular expressions interpret as a backspace
-- character rather than a word boundary, so card numbers were never matched and the phone
-- pattern that follows redacted them only partially, leaving trailing digits in the output.

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
    -- \y is the word boundary in PostgreSQL regular expressions (\b means backspace).
    -- The number must start and end with a digit so that adjacent separators are kept.
    cleaned := regexp_replace(cleaned, '\y\d(?:[ -]*\d){12,18}\y', '[REDACTED_CARD]', 'g');
    cleaned := regexp_replace(cleaned, '(?:\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{3,4}', '[REDACTED_PHONE]', 'g');
    RETURN cleaned;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
