\echo 'Validacao manual da migration 009 - matching'

BEGIN;

ALTER TABLE orders DISABLE TRIGGER trg_match_order_after_insert;

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
    v_seller_2_user_id BIGINT;

    v_buy_order_id BIGINT;
    v_sell_order_id BIGINT;
    v_sell_order_2_id BIGINT;
    v_trade_id BIGINT;
    v_first_trade_sell_order_id BIGINT;
    v_trade_count INTEGER;
    v_count INTEGER;
    v_release_amount NUMERIC(28,10);
BEGIN
    v_base_symbol := ('M9B' || v_suffix)::VARCHAR(10);
    v_quote_symbol := ('M9Q' || v_suffix)::VARCHAR(10);
    v_market_symbol := (v_base_symbol || '/' || v_quote_symbol)::VARCHAR(20);

    INSERT INTO assets (symbol, name, decimal_places, is_active)
    VALUES
        (v_base_symbol, 'Ativo base validacao 009', 8, true),
        (v_quote_symbol, 'Ativo quote validacao 009', 2, true);

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
    );

    SELECT
        market_id,
        base_asset_id,
        quote_asset_id,
        symbol
    INTO
        v_market_id,
        v_base_asset_id,
        v_quote_asset_id,
        v_market_symbol
    FROM markets
    WHERE symbol = v_market_symbol
      AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mercado ativo temporario nao encontrado para validacao 009';
    END IF;

    INSERT INTO users (name, email, is_active)
    VALUES ('Validacao 009 Comprador', 'validacao-009-comprador-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_buyer_user_id;

    INSERT INTO users (name, email, is_active)
    VALUES ('Validacao 009 Vendedor 1', 'validacao-009-vendedor-1-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_seller_user_id;

    INSERT INTO users (name, email, is_active)
    VALUES ('Validacao 009 Vendedor 2', 'validacao-009-vendedor-2-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_seller_2_user_id;

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
        (v_seller_user_id, v_quote_asset_id, 0.0000000000, 0.0000000000),
        (v_seller_2_user_id, v_base_asset_id, 0.0000000000, 0.0000000000),
        (v_seller_2_user_id, v_quote_asset_id, 0.0000000000, 0.0000000000);

    CALL sp_deposit(v_buyer_user_id, v_quote_symbol, 1000000.0000000000, 'Saldo temporario para validacao 009');
    CALL sp_deposit(v_seller_user_id, v_base_symbol, 1000.0000000000, 'Saldo temporario para validacao 009');
    CALL sp_deposit(v_seller_2_user_id, v_base_symbol, 1000.0000000000, 'Saldo temporario para validacao 009');

    -- 1. Fill total simples.
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

    PERFORM fn_match_order(v_buy_order_id);

    SELECT COUNT(*)
    INTO v_trade_count
    FROM trades
    WHERE buy_order_id = v_buy_order_id
      AND sell_order_id = v_sell_order_id;

    IF v_trade_count <> 1 THEN
        RAISE EXCEPTION 'Fill total simples falhou: esperado 1 trade, encontrado %', v_trade_count;
    END IF;

    PERFORM 1
    FROM orders
    WHERE order_id IN (v_buy_order_id, v_sell_order_id)
      AND status = 'FILLED'
      AND remaining_quantity = 0.0000000000
      AND reserved_amount = 0.0000000000
    GROUP BY status
    HAVING COUNT(*) = 2;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fill total simples falhou: ordens nao ficaram FILLED com remaining e reserva zerados';
    END IF;

    RAISE NOTICE 'Teste aprovado: fill total simples';

    -- 2. Partial fill.
    v_sell_order_id := NULL;
    v_buy_order_id := NULL;

    CALL sp_place_order(
        v_seller_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        110.0000000000,
        0.0500000000,
        v_sell_order_id
    );

    CALL sp_place_order(
        v_buyer_user_id,
        v_market_symbol,
        'BUY'::enum_order_side,
        110.0000000000,
        0.1000000000,
        v_buy_order_id
    );

    PERFORM fn_match_order(v_buy_order_id);

    PERFORM 1
    FROM orders
    WHERE order_id = v_sell_order_id
      AND status = 'FILLED'
      AND remaining_quantity = 0.0000000000
      AND reserved_amount = 0.0000000000;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partial fill falhou: SELL nao ficou FILLED';
    END IF;

    PERFORM 1
    FROM orders
    WHERE order_id = v_buy_order_id
      AND status = 'PARTIAL'
      AND remaining_quantity = 0.0500000000
      AND reserved_amount = 5.5000000000;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partial fill falhou: BUY nao ficou PARTIAL com remaining/reserva corretos';
    END IF;

    CALL sp_cancel_order(v_buyer_user_id, v_buy_order_id);

    RAISE NOTICE 'Teste aprovado: partial fill';

    -- 3. Refund de BUY.
    v_sell_order_id := NULL;
    v_buy_order_id := NULL;

    CALL sp_place_order(
        v_seller_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        98.0000000000,
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

    PERFORM fn_match_order(v_buy_order_id);

    SELECT trade_id
    INTO v_trade_id
    FROM trades
    WHERE buy_order_id = v_buy_order_id
      AND sell_order_id = v_sell_order_id;

    SELECT amount
    INTO v_release_amount
    FROM wallet_movements
    WHERE trade_id = v_trade_id
      AND order_id = v_buy_order_id
      AND movement_type = 'ORDER_RELEASE';

    IF v_release_amount IS DISTINCT FROM 0.2000000000 THEN
        RAISE EXCEPTION 'Refund de BUY falhou: esperado 0.2000000000, encontrado %', v_release_amount;
    END IF;

    RAISE NOTICE 'Teste aprovado: refund de BUY';

    -- 4. Multiplas contrapartes.
    v_sell_order_id := NULL;
    v_sell_order_2_id := NULL;
    v_buy_order_id := NULL;

    CALL sp_place_order(
        v_seller_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        100.0000000000,
        0.0500000000,
        v_sell_order_id
    );

    CALL sp_place_order(
        v_seller_2_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        101.0000000000,
        0.0500000000,
        v_sell_order_2_id
    );

    CALL sp_place_order(
        v_buyer_user_id,
        v_market_symbol,
        'BUY'::enum_order_side,
        105.0000000000,
        0.1000000000,
        v_buy_order_id
    );

    PERFORM fn_match_order(v_buy_order_id);

    SELECT COUNT(*)
    INTO v_trade_count
    FROM trades
    WHERE buy_order_id = v_buy_order_id;

    IF v_trade_count <> 2 THEN
        RAISE EXCEPTION 'Multiplas contrapartes falhou: esperado 2 trades, encontrado %', v_trade_count;
    END IF;

    PERFORM 1
    FROM orders
    WHERE order_id IN (v_buy_order_id, v_sell_order_id, v_sell_order_2_id)
      AND status = 'FILLED'
      AND remaining_quantity = 0.0000000000
    GROUP BY status
    HAVING COUNT(*) = 3;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Multiplas contrapartes falhou: BUY nao consumiu as duas SELLs';
    END IF;

    RAISE NOTICE 'Teste aprovado: multiplas contrapartes';

    -- 5. Price-time priority por preco.
    v_sell_order_id := NULL;
    v_sell_order_2_id := NULL;
    v_buy_order_id := NULL;

    CALL sp_place_order(
        v_seller_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        102.0000000000,
        0.0500000000,
        v_sell_order_id
    );

    CALL sp_place_order(
        v_seller_2_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        99.0000000000,
        0.0500000000,
        v_sell_order_2_id
    );

    CALL sp_place_order(
        v_buyer_user_id,
        v_market_symbol,
        'BUY'::enum_order_side,
        105.0000000000,
        0.0500000000,
        v_buy_order_id
    );

    PERFORM fn_match_order(v_buy_order_id);

    SELECT sell_order_id
    INTO v_first_trade_sell_order_id
    FROM trades
    WHERE buy_order_id = v_buy_order_id
    ORDER BY trade_id ASC
    LIMIT 1;

    IF v_first_trade_sell_order_id <> v_sell_order_2_id THEN
        RAISE EXCEPTION 'Price priority falhou: primeira SELL executada foi %, esperado %',
            v_first_trade_sell_order_id, v_sell_order_2_id;
    END IF;

    CALL sp_cancel_order(v_seller_user_id, v_sell_order_id);

    RAISE NOTICE 'Teste aprovado: price-time priority por preco';

    -- 5b. Price-time priority por order_id em empate.
    v_sell_order_id := NULL;
    v_sell_order_2_id := NULL;
    v_buy_order_id := NULL;

    CALL sp_place_order(
        v_seller_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        103.0000000000,
        0.0500000000,
        v_sell_order_id
    );

    CALL sp_place_order(
        v_seller_2_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        103.0000000000,
        0.0500000000,
        v_sell_order_2_id
    );

    CALL sp_place_order(
        v_buyer_user_id,
        v_market_symbol,
        'BUY'::enum_order_side,
        105.0000000000,
        0.0500000000,
        v_buy_order_id
    );

    PERFORM fn_match_order(v_buy_order_id);

    SELECT sell_order_id
    INTO v_first_trade_sell_order_id
    FROM trades
    WHERE buy_order_id = v_buy_order_id
    ORDER BY trade_id ASC
    LIMIT 1;

    IF v_first_trade_sell_order_id <> LEAST(v_sell_order_id, v_sell_order_2_id) THEN
        RAISE EXCEPTION 'Time priority falhou: primeira SELL executada foi %, esperado %',
            v_first_trade_sell_order_id, LEAST(v_sell_order_id, v_sell_order_2_id);
    END IF;

    CALL sp_cancel_order(v_seller_2_user_id, v_sell_order_2_id);

    RAISE NOTICE 'Teste aprovado: price-time priority por order_id em empate';

    -- 6. BUY abaixo do ASK nao executa.
    v_sell_order_id := NULL;
    v_buy_order_id := NULL;

    CALL sp_place_order(
        v_seller_user_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        120.0000000000,
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

    PERFORM fn_match_order(v_buy_order_id);

    SELECT COUNT(*)
    INTO v_trade_count
    FROM trades
    WHERE buy_order_id = v_buy_order_id
       OR sell_order_id = v_sell_order_id;

    IF v_trade_count <> 0 THEN
        RAISE EXCEPTION 'BUY abaixo do ASK falhou: esperado 0 trades, encontrado %', v_trade_count;
    END IF;

    PERFORM 1
    FROM orders
    WHERE order_id IN (v_buy_order_id, v_sell_order_id)
      AND status = 'OPEN'
    GROUP BY status
    HAVING COUNT(*) = 2;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'BUY abaixo do ASK falhou: ordens nao permaneceram OPEN';
    END IF;

    CALL sp_cancel_order(v_buyer_user_id, v_buy_order_id);
    CALL sp_cancel_order(v_seller_user_id, v_sell_order_id);

    RAISE NOTICE 'Teste aprovado: BUY abaixo do ASK nao executa';

    -- 7. Wallet movements.
    SELECT COUNT(*)
    INTO v_count
    FROM wallet_movements
    WHERE trade_id IN (
        SELECT trade_id
        FROM trades
        WHERE market_id = v_market_id
    )
      AND movement_type = 'TRADE_DEBIT';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Wallet movements falhou: nenhum TRADE_DEBIT encontrado';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM wallet_movements
    WHERE trade_id IN (
        SELECT trade_id
        FROM trades
        WHERE market_id = v_market_id
    )
      AND movement_type = 'TRADE_CREDIT';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Wallet movements falhou: nenhum TRADE_CREDIT encontrado';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM wallet_movements
    WHERE trade_id IN (
        SELECT trade_id
        FROM trades
        WHERE market_id = v_market_id
    )
      AND movement_type = 'ORDER_RELEASE';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Wallet movements falhou: nenhum ORDER_RELEASE encontrado';
    END IF;

    RAISE NOTICE 'Teste aprovado: wallet_movements preenchida';

    -- 8. Auditoria.
    SELECT COUNT(*)
    INTO v_count
    FROM order_audit_log
    WHERE trade_id IN (
        SELECT trade_id
        FROM trades
        WHERE market_id = v_market_id
    )
      AND event_type = 'ORDER_FILLED';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Auditoria falhou: nenhum ORDER_FILLED encontrado';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM order_audit_log
    WHERE trade_id IN (
        SELECT trade_id
        FROM trades
        WHERE market_id = v_market_id
    )
      AND event_type = 'ORDER_PARTIALLY_FILLED';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Auditoria falhou: nenhum ORDER_PARTIALLY_FILLED encontrado';
    END IF;

    RAISE NOTICE 'Teste aprovado: order_audit_log preenchida';

    -- 9. Seguranca financeira.
    SELECT COUNT(*)
    INTO v_count
    FROM wallets
    WHERE available_balance < 0
       OR locked_balance < 0;

    IF v_count > 0 THEN
        RAISE EXCEPTION 'Seguranca financeira falhou: % wallets com saldo negativo', v_count;
    END IF;

    RAISE NOTICE 'Teste aprovado: nenhuma wallet ficou com saldo negativo';
    RAISE NOTICE 'Validacao manual da migration 009 concluida com sucesso';
END;
$$;

ALTER TABLE orders ENABLE TRIGGER trg_match_order_after_insert;

ROLLBACK;
