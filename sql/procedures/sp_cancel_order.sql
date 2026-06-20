CREATE OR REPLACE PROCEDURE sp_cancel_order(
    IN p_user_id BIGINT,
    IN p_order_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_base_asset_id INTEGER;
    v_quote_asset_id INTEGER;
    v_wallet_asset_id INTEGER;
    v_wallet_id BIGINT;
    v_available_balance NUMERIC(28,10);
    v_locked_balance NUMERIC(28,10);
BEGIN
    SELECT *
    INTO v_order
    FROM orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ordem nao encontrada. order_id=%', p_order_id;
    END IF;

    IF v_order.user_id <> p_user_id THEN
        RAISE EXCEPTION 'A ordem % nao pertence ao usuario %', p_order_id, p_user_id;
    END IF;

    IF v_order.status NOT IN ('OPEN', 'PARTIAL') THEN
        RAISE EXCEPTION 'A ordem % nao pode ser cancelada porque o status e %',
            p_order_id, v_order.status;
    END IF;

    IF v_order.reserved_amount <= 0 THEN
        RAISE EXCEPTION 'A ordem % nao possui saldo reservado para liberar. reserved_amount=%',
            p_order_id, v_order.reserved_amount;
    END IF;

    SELECT
        base_asset_id,
        quote_asset_id
    INTO
        v_base_asset_id,
        v_quote_asset_id
    FROM markets
    WHERE market_id = v_order.market_id;

    IF v_order.side = 'BUY' THEN
        v_wallet_asset_id := v_quote_asset_id;
    ELSE
        v_wallet_asset_id := v_base_asset_id;
    END IF;

    SELECT
        wallet_id,
        available_balance,
        locked_balance
    INTO
        v_wallet_id,
        v_available_balance,
        v_locked_balance
    FROM wallets
    WHERE user_id = p_user_id
      AND asset_id = v_wallet_asset_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Carteira nao encontrada para cancelamento. user_id=%, asset_id=%',
            p_user_id, v_wallet_asset_id;
    END IF;

    IF v_locked_balance < v_order.reserved_amount THEN
        RAISE EXCEPTION 'Saldo bloqueado insuficiente para cancelar ordem %. bloqueado=%, reservado=%',
            p_order_id, v_locked_balance, v_order.reserved_amount;
    END IF;

    UPDATE wallets
    SET
        available_balance = available_balance + v_order.reserved_amount,
        locked_balance = locked_balance - v_order.reserved_amount,
        updated_at = clock_timestamp()
    WHERE wallet_id = v_wallet_id
    RETURNING
        available_balance,
        locked_balance
    INTO
        v_available_balance,
        v_locked_balance;

    INSERT INTO wallet_movements (
        wallet_id,
        user_id,
        asset_id,
        order_id,
        movement_type,
        amount,
        available_balance_after,
        locked_balance_after,
        description
    )
    VALUES (
        v_wallet_id,
        p_user_id,
        v_wallet_asset_id,
        p_order_id,
        'CANCEL_RELEASE',
        v_order.reserved_amount,
        v_available_balance,
        v_locked_balance,
        'Saldo liberado pelo cancelamento da ordem'
    );

    UPDATE orders
    SET
        status = 'CANCELED',
        reserved_amount = 0,
        updated_at = clock_timestamp()
    WHERE order_id = p_order_id;

    INSERT INTO order_audit_log (
        order_id,
        old_status,
        new_status,
        old_remaining_quantity,
        new_remaining_quantity,
        event_type,
        reason
    )
    VALUES (
        p_order_id,
        v_order.status,
        'CANCELED',
        v_order.remaining_quantity,
        v_order.remaining_quantity,
        'ORDER_CANCELED',
        'Ordem cancelada por sp_cancel_order'
    );

    RAISE NOTICE 'Ordem cancelada. order_id=%, user_id=%', p_order_id, p_user_id;
END;
$$;
