CREATE OR REPLACE FUNCTION trg_match_order_after_insert_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_match_order(NEW.order_id);

    RETURN NEW;
END;
$$;
