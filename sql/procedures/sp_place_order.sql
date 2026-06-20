CREATE OR REPLACE PROCEDURE sp_place_order(
    IN p_user_id BIGINT,
    IN p_market_symbol VARCHAR(20),
    IN p_side enum_order_side,
    IN p_price NUMERIC(28,10),
    IN p_quantity NUMERIC(28,10),
    INOUT p_order_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_market_id INTEGER;
    v_base_asset_id INTEGER;
    v_quote_asset_id INTEGER;
    v_wallet_asset_id INTEGER;
    v_wallet_id BIGINT;
    v_reserved_amount NUMERIC(28,10);
    v_available_balance NUMERIC(28,10);
    v_locked_balance NUMERIC(28,10);
BEGIN
    IF p_price <= 0 THEN
        RAISE EXCEPTION 'O preco da ordem deve ser positivo. Recebido: %', p_price;
    END IF;

    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'A quantidade da ordem deve ser positiva. Recebido: %', p_quantity;
    END IF;

    PERFORM 1
    FROM users
    WHERE user_id = p_user_id
      AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuario ativo nao encontrado. user_id=%', p_user_id;
    END IF;

    SELECT
        market_id,
        base_asset_id,
        quote_asset_id
    INTO
        v_market_id,
        v_base_asset_id,
        v_quote_asset_id
    FROM markets
    WHERE symbol = p_market_symbol
      AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mercado ativo nao encontrado. symbol=%', p_market_symbol;
    END IF;

    IF p_side = 'BUY' THEN
        v_wallet_asset_id := v_quote_asset_id;
        v_reserved_amount := p_price * p_quantity;
    ELSIF p_side = 'SELL' THEN
        v_wallet_asset_id := v_base_asset_id;
        v_reserved_amount := p_quantity;
    ELSE
        RAISE EXCEPTION 'Lado da ordem invalido: %', p_side;
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
        RAISE EXCEPTION 'Carteira nao encontrada para user_id=% e asset_id=%',
            p_user_id, v_wallet_asset_id;
    END IF;

    IF v_available_balance < v_reserved_amount THEN
        RAISE EXCEPTION 'Saldo disponivel insuficiente. disponivel=%, necessario=%',
            v_available_balance, v_reserved_amount;
    END IF;

    UPDATE wallets
    SET
        available_balance = available_balance - v_reserved_amount,
        locked_balance = locked_balance + v_reserved_amount,
        updated_at = clock_timestamp()
    WHERE wallet_id = v_wallet_id
    RETURNING
        available_balance,
        locked_balance
    INTO
        v_available_balance,
        v_locked_balance;

    INSERT INTO orders (
        user_id,
        market_id,
        side,
        price,
        quantity,
        remaining_quantity,
        reserved_amount,
        status
    )
    VALUES (
        p_user_id,
        v_market_id,
        p_side,
        p_price,
        p_quantity,
        p_quantity,
        v_reserved_amount,
        'OPEN'
    )
    RETURNING order_id INTO p_order_id;

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
        'ORDER_LOCK',
        -v_reserved_amount,
        v_available_balance,
        v_locked_balance,
        'Saldo bloqueado para ordem'
    );

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
        NULL,
        'OPEN',
        NULL,
        p_quantity,
        'ORDER_CREATED',
        'Ordem criada por sp_place_order'
    );

    RAISE NOTICE 'Ordem criada. order_id=%, user_id=%, mercado=%, lado=%',
        p_order_id, p_user_id, p_market_symbol, p_side;
END;
$$;
