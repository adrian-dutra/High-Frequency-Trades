\echo 'Validacao da trigger automatica de matching'

BEGIN;

DO $$
DECLARE
    v_suffix TEXT := substring(md5(clock_timestamp()::TEXT || txid_current()::TEXT), 1, 4);
    v_base_symbol VARCHAR(10);
    v_quote_symbol VARCHAR(10);
    v_market_symbol VARCHAR(20);
    v_base_asset_id INTEGER;
    v_quote_asset_id INTEGER;
    v_market_id INTEGER;

    v_buyer_user_id BIGINT;
    v_seller_user_id BIGINT;

    v_buy_order_id BIGINT;
    v_sell_order_id BIGINT;
    v_trade_id BIGINT;
    v_trade_count INTEGER;
    v_count INTEGER;
BEGIN
    v_base_symbol := ('T9B' || v_suffix)::VARCHAR(10);
    v_quote_symbol := ('T9Q' || v_suffix)::VARCHAR(10);
    v_market_symbol := (v_base_symbol || '/' || v_quote_symbol)::VARCHAR(20);

    INSERT INTO assets (symbol, name, decimal_places, is_active)
    VALUES
        (v_base_symbol, 'Ativo base validacao trigger 009', 8, true),
        (v_quote_symbol, 'Ativo quote validacao trigger 009', 2, true);

    SELECT asset_id
    INTO v_base_asset_id
    FROM assets
    WHERE symbol = v_base_symbol
      AND is_active = true;

    SELECT asset_id
    INTO v_quote_asset_id
    FROM assets
    WHERE symbol = v_quote_symbol
      AND is_active = true;

    INSERT INTO markets (
        base_asset_id,
        quote_asset_id,
        symbol,
        min_order_quantity,
        price_tick,
        quantity_step,
        is_active
    )
    VALUES (
        v_base_asset_id,
        v_quote_asset_id,
        v_market_symbol,
        0.0000000100,
        0.0100000000,
        0.0000000100,
        true
    )
    RETURNING market_id INTO v_market_id;

    INSERT INTO users (name, email, is_active)
    VALUES ('Validacao trigger 009 comprador', 'validacao-trigger-009-comprador-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_buyer_user_id;

    INSERT INTO users (name, email, is_active)
    VALUES ('Validacao trigger 009 vendedor', 'validacao-trigger-009-vendedor-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_seller_user_id;

    INSERT INTO wallets (
        user_id,
        asset_id,
        available_balance,
        locked_balance
    )
    VALUES
        (v_buyer_user_id, v_base_asset_id, 0.0000000000, 0.0000000000),
        (v_buyer_user_id, v_quote_asset_id, 0.0000000000, 0.0000000000),
        (v_seller_user_id, v_base_asset_id, 0.0000000000, 0.0000000000),
        (v_seller_user_id, v_quote_asset_id, 0.0000000000, 0.0000000000);

    CALL sp_deposit(v_buyer_user_id, v_quote_symbol, 1000000.0000000000, 'Saldo temporario para validacao da trigger 009');
    CALL sp_deposit(v_seller_user_id, v_base_symbol, 1000.0000000000, 'Saldo temporario para validacao da trigger 009');

    -- Cenario 1: SELL passiva, BUY entrante.
    v_sell_order_id := NULL;
    v_buy_order_id := NULL;

    CALL sp_place_order(
        v_seller_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        100.0000000000,
        0.1000000000,
        v_sell_order_id
    );

    CALL sp_place_order(
        v_buyer_user_id,
        v_market_symbol,
        'BUY'::enum_order_side,
        100.0000000000,
        0.1000000000,
        v_buy_order_id
    );

    SELECT COUNT(*)
    INTO v_trade_count
    FROM trades
    WHERE buy_order_id = v_buy_order_id
      AND sell_order_id = v_sell_order_id;

    IF v_trade_count <> 1 THEN
        RAISE EXCEPTION 'Trigger com BUY entrante falhou: esperado 1 trade, encontrado %', v_trade_count;
    END IF;

    SELECT trade_id
    INTO v_trade_id
    FROM trades
    WHERE buy_order_id = v_buy_order_id
      AND sell_order_id = v_sell_order_id;

    SELECT COUNT(*)
    INTO v_count
    FROM orders
    WHERE order_id IN (v_buy_order_id, v_sell_order_id)
      AND status = 'FILLED'
      AND remaining_quantity = 0.0000000000
      AND reserved_amount = 0.0000000000;

    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Trigger com BUY entrante falhou: BUY e SELL nao ficaram FILLED com saldos de ordem zerados';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM wallet_movements
    WHERE trade_id = v_trade_id
      AND movement_type = 'TRADE_DEBIT';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Trigger com BUY entrante falhou: wallet_movements nao recebeu TRADE_DEBIT';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM wallet_movements
    WHERE trade_id = v_trade_id
      AND movement_type = 'TRADE_CREDIT';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Trigger com BUY entrante falhou: wallet_movements nao recebeu TRADE_CREDIT';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM order_audit_log
    WHERE trade_id = v_trade_id
      AND event_type = 'ORDER_FILLED';

    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Trigger com BUY entrante falhou: order_audit_log nao recebeu ORDER_FILLED para as duas ordens';
    END IF;

    RAISE NOTICE 'Teste aprovado: matching automatico com BUY entrante';

    -- Cenario 2: BUY passiva, SELL entrante.
    v_sell_order_id := NULL;
    v_buy_order_id := NULL;

    CALL sp_place_order(
        v_buyer_user_id,
        v_market_symbol,
        'BUY'::enum_order_side,
        95.0000000000,
        0.2000000000,
        v_buy_order_id
    );

    CALL sp_place_order(
        v_seller_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        95.0000000000,
        0.2000000000,
        v_sell_order_id
    );

    SELECT COUNT(*)
    INTO v_trade_count
    FROM trades
    WHERE buy_order_id = v_buy_order_id
      AND sell_order_id = v_sell_order_id;

    IF v_trade_count <> 1 THEN
        RAISE EXCEPTION 'Trigger com SELL entrante falhou: esperado 1 trade, encontrado %', v_trade_count;
    END IF;

    SELECT trade_id
    INTO v_trade_id
    FROM trades
    WHERE buy_order_id = v_buy_order_id
      AND sell_order_id = v_sell_order_id;

    SELECT COUNT(*)
    INTO v_count
    FROM orders
    WHERE order_id IN (v_buy_order_id, v_sell_order_id)
      AND status = 'FILLED'
      AND remaining_quantity = 0.0000000000
      AND reserved_amount = 0.0000000000;

    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Trigger com SELL entrante falhou: BUY e SELL nao ficaram FILLED com saldos de ordem zerados';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM wallet_movements
    WHERE trade_id = v_trade_id
      AND movement_type = 'TRADE_DEBIT';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Trigger com SELL entrante falhou: wallet_movements nao recebeu TRADE_DEBIT';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM wallet_movements
    WHERE trade_id = v_trade_id
      AND movement_type = 'TRADE_CREDIT';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Trigger com SELL entrante falhou: wallet_movements nao recebeu TRADE_CREDIT';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM order_audit_log
    WHERE trade_id = v_trade_id
      AND event_type = 'ORDER_FILLED';

    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Trigger com SELL entrante falhou: order_audit_log nao recebeu ORDER_FILLED para as duas ordens';
    END IF;

    RAISE NOTICE 'Teste aprovado: matching automatico com SELL entrante';

    SELECT COUNT(*)
    INTO v_count
    FROM wallets
    WHERE available_balance < 0
       OR locked_balance < 0;

    IF v_count > 0 THEN
        RAISE EXCEPTION 'Seguranca financeira falhou: % wallets com saldo negativo', v_count;
    END IF;

    RAISE NOTICE 'Teste aprovado: nenhuma wallet ficou com saldo negativo';
    RAISE NOTICE 'Validacao da trigger de matching concluida com sucesso';
END;
$$;

ROLLBACK;
