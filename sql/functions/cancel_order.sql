CREATE OR REPLACE FUNCTION cancel_order(
    p_user_id BIGINT,
    p_order_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    CALL sp_cancel_order(p_user_id, p_order_id);
END;
$$;
