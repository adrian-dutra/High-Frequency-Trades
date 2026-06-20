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
