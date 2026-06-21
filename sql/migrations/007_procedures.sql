CREATE OR REPLACE PROCEDURE sp_deposit(
    IN p_user_id BIGINT,
    IN p_asset_symbol VARCHAR(10),
    IN p_amount NUMERIC(28,10),
    IN p_description TEXT DEFAULT 'Deposito manual'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_asset_id INTEGER;
    v_wallet_id BIGINT;
    v_available_balance NUMERIC(28,10);
    v_locked_balance NUMERIC(28,10);
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'O valor do deposito deve ser positivo. Recebido: %', p_amount;
    END IF;

    PERFORM 1
    FROM users
    WHERE user_id = p_user_id
      AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuario ativo nao encontrado. user_id=%', p_user_id;
    END IF;

    SELECT asset_id
    INTO v_asset_id
    FROM assets
    WHERE symbol = p_asset_symbol
      AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ativo habilitado nao encontrado. symbol=%', p_asset_symbol;
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
      AND asset_id = v_asset_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Carteira nao encontrada para deposito. user_id=%, asset_id=%',
            p_user_id, v_asset_id;
    END IF;

    UPDATE wallets
    SET
        available_balance = available_balance + p_amount,
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
        movement_type,
        amount,
        available_balance_after,
        locked_balance_after,
        description
    )
    VALUES (
        v_wallet_id,
        p_user_id,
        v_asset_id,
        'DEPOSIT',
        p_amount,
        v_available_balance,
        v_locked_balance,
        p_description
    );

    RAISE NOTICE 'Deposito concluido. user_id=%, ativo=%, valor=%',
        p_user_id, p_asset_symbol, p_amount;
END;
$$;

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
