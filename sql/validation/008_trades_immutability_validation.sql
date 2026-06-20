\echo 'Validacao da migration 008 - imutabilidade de trades'

BEGIN;

ALTER TABLE orders DISABLE TRIGGER trg_match_order_after_insert;

DO $$
DECLARE
    v_market_id INTEGER;
    v_market_symbol VARCHAR(20);
    v_base_asset_id INTEGER;
    v_quote_asset_id INTEGER;
    v_buyer_user_id BIGINT;
    v_seller_user_id BIGINT;
    v_buy_order_id BIGINT;
    v_sell_order_id BIGINT;
    v_trade_id BIGINT;
    v_expected_message TEXT := 'Trades sao imutaveis e nao podem ser atualizados ou removidos';
BEGIN
    SELECT
        market_id,
        symbol,
        base_asset_id,
        quote_asset_id
    INTO
        v_market_id,
        v_market_symbol,
        v_base_asset_id,
        v_quote_asset_id
    FROM markets
    WHERE is_active = true
    ORDER BY market_id
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Nenhum mercado ativo encontrado para validacao da migration 008';
    END IF;

    SELECT user_id
    INTO v_buyer_user_id
    FROM users
    WHERE is_active = true
    ORDER BY user_id
    LIMIT 1;

    SELECT user_id
    INTO v_seller_user_id
    FROM users
    WHERE is_active = true
      AND user_id <> v_buyer_user_id
    ORDER BY user_id
    LIMIT 1;

    IF v_buyer_user_id IS NULL OR v_seller_user_id IS NULL THEN
        RAISE EXCEPTION 'Sao necessarios dois usuarios ativos diferentes para validar a migration 008';
    END IF;

    INSERT INTO wallets (
        user_id,
        asset_id,
        available_balance,
        locked_balance
    )
    VALUES
        (v_buyer_user_id, v_quote_asset_id, 1000000.0000000000, 0.0000000000),
        (v_seller_user_id, v_base_asset_id, 1000.0000000000, 0.0000000000)
    ON CONFLICT (user_id, asset_id) DO UPDATE
    SET
        available_balance = EXCLUDED.available_balance,
        locked_balance = EXCLUDED.locked_balance,
        updated_at = clock_timestamp();

    v_buy_order_id := NULL;
    CALL sp_place_order(
        v_buyer_user_id,
        v_market_symbol,
        'BUY'::enum_order_side,
        100.0000000000,
        1.0000000000,
        v_buy_order_id
    );

    IF v_buy_order_id IS NULL THEN
        RAISE EXCEPTION 'Validacao falhou: ordem BUY nao retornou order_id';
    END IF;

    RAISE NOTICE 'Ordem BUY criada para validacao. order_id=%', v_buy_order_id;

    v_sell_order_id := NULL;
    CALL sp_place_order(
        v_seller_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        100.0000000000,
        1.0000000000,
        v_sell_order_id
    );

    IF v_sell_order_id IS NULL THEN
        RAISE EXCEPTION 'Validacao falhou: ordem SELL nao retornou order_id';
    END IF;

    RAISE NOTICE 'Ordem SELL criada para validacao. order_id=%', v_sell_order_id;

    INSERT INTO trades (
        market_id,
        buy_order_id,
        sell_order_id,
        buyer_user_id,
        seller_user_id,
        price,
        quantity
    )
    VALUES (
        v_market_id,
        v_buy_order_id,
        v_sell_order_id,
        v_buyer_user_id,
        v_seller_user_id,
        100.0000000000,
        1.0000000000
    )
    RETURNING trade_id INTO v_trade_id;

    IF v_trade_id IS NULL THEN
        RAISE EXCEPTION 'Validacao falhou: INSERT em trades nao retornou trade_id';
    END IF;

    RAISE NOTICE 'INSERT em trades permitido conforme esperado. trade_id=%', v_trade_id;

    BEGIN
        UPDATE trades
        SET price = 101.0000000000
        WHERE trade_id = v_trade_id;

        RAISE EXCEPTION 'Validacao falhou: UPDATE em trades foi permitido indevidamente';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'Validacao falhou: UPDATE em trades foi permitido indevidamente' THEN
                RAISE;
            END IF;

            IF SQLERRM <> v_expected_message THEN
                RAISE EXCEPTION 'Validacao falhou: UPDATE em trades retornou mensagem inesperada: %', SQLERRM;
            END IF;

            RAISE NOTICE 'UPDATE em trades bloqueado como esperado. Mensagem: %', SQLERRM;
    END;

    BEGIN
        DELETE FROM trades
        WHERE trade_id = v_trade_id;

        RAISE EXCEPTION 'Validacao falhou: DELETE em trades foi permitido indevidamente';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'Validacao falhou: DELETE em trades foi permitido indevidamente' THEN
                RAISE;
            END IF;

            IF SQLERRM <> v_expected_message THEN
                RAISE EXCEPTION 'Validacao falhou: DELETE em trades retornou mensagem inesperada: %', SQLERRM;
            END IF;

            RAISE NOTICE 'DELETE em trades bloqueado como esperado. Mensagem: %', SQLERRM;
    END;

    RAISE NOTICE 'Validacao da migration 008 concluida com sucesso';
END;
$$;

ALTER TABLE orders ENABLE TRIGGER trg_match_order_after_insert;

ROLLBACK;
