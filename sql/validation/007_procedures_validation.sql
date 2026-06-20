\echo 'Validacao da migration 007 - procedures'

BEGIN;

ALTER TABLE orders DISABLE TRIGGER trg_match_order_after_insert;

DO $$
DECLARE
    v_market_id INTEGER;
    v_base_asset_id INTEGER;
    v_quote_asset_id INTEGER;
    v_buyer_user_id BIGINT;
    v_seller_user_id BIGINT;
    v_poor_buyer_user_id BIGINT;
    v_poor_seller_user_id BIGINT;
    v_other_user_id BIGINT;
    v_buy_order_id BIGINT;
    v_sell_order_id BIGINT;
    v_cancel_order_id BIGINT;
    v_other_cancel_order_id BIGINT;
    v_initial_quote_available NUMERIC(28,10);
    v_initial_quote_locked NUMERIC(28,10);
    v_initial_base_available NUMERIC(28,10);
    v_initial_base_locked NUMERIC(28,10);
    v_after_quote_available NUMERIC(28,10);
    v_after_quote_locked NUMERIC(28,10);
    v_after_base_available NUMERIC(28,10);
    v_after_base_locked NUMERIC(28,10);
    v_expected_reserved NUMERIC(28,10);
    v_count INTEGER;
BEGIN
    SELECT
        market_id,
        base_asset_id,
        quote_asset_id
    INTO
        v_market_id,
        v_base_asset_id,
        v_quote_asset_id
    FROM markets
    WHERE symbol = 'BTC/USDT'
      AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mercado BTC/USDT ativo nao encontrado para validacao';
    END IF;

    INSERT INTO users (name, email, is_active)
    VALUES
        ('Validacao 007 Comprador', 'validacao-007-comprador@example.com', true),
        ('Validacao 007 Vendedor', 'validacao-007-vendedor@example.com', true),
        ('Validacao 007 Comprador Sem Saldo', 'validacao-007-comprador-sem-saldo@example.com', true),
        ('Validacao 007 Vendedor Sem Saldo', 'validacao-007-vendedor-sem-saldo@example.com', true),
        ('Validacao 007 Outro Usuario', 'validacao-007-outro-usuario@example.com', true);

    SELECT user_id INTO v_buyer_user_id
    FROM users
    WHERE email = 'validacao-007-comprador@example.com';

    SELECT user_id INTO v_seller_user_id
    FROM users
    WHERE email = 'validacao-007-vendedor@example.com';

    SELECT user_id INTO v_poor_buyer_user_id
    FROM users
    WHERE email = 'validacao-007-comprador-sem-saldo@example.com';

    SELECT user_id INTO v_poor_seller_user_id
    FROM users
    WHERE email = 'validacao-007-vendedor-sem-saldo@example.com';

    SELECT user_id INTO v_other_user_id
    FROM users
    WHERE email = 'validacao-007-outro-usuario@example.com';

    INSERT INTO wallets (
        user_id,
        asset_id,
        available_balance,
        locked_balance
    )
    VALUES
        (v_buyer_user_id, v_quote_asset_id, 1000.0000000000, 0.0000000000),
        (v_buyer_user_id, v_base_asset_id, 0.0000000000, 0.0000000000),
        (v_seller_user_id, v_quote_asset_id, 0.0000000000, 0.0000000000),
        (v_seller_user_id, v_base_asset_id, 2.0000000000, 0.0000000000),
        (v_poor_buyer_user_id, v_quote_asset_id, 1.0000000000, 0.0000000000),
        (v_poor_buyer_user_id, v_base_asset_id, 0.0000000000, 0.0000000000),
        (v_poor_seller_user_id, v_quote_asset_id, 0.0000000000, 0.0000000000),
        (v_poor_seller_user_id, v_base_asset_id, 0.0000000000, 0.0000000000),
        (v_other_user_id, v_quote_asset_id, 1000.0000000000, 0.0000000000),
        (v_other_user_id, v_base_asset_id, 2.0000000000, 0.0000000000);

    SELECT
        available_balance,
        locked_balance
    INTO
        v_initial_quote_available,
        v_initial_quote_locked
    FROM wallets
    WHERE user_id = v_buyer_user_id
      AND asset_id = v_quote_asset_id;

    v_buy_order_id := NULL;
    CALL sp_place_order(
        v_buyer_user_id,
        'BTC/USDT',
        'BUY'::enum_order_side,
        100.0000000000,
        2.0000000000,
        v_buy_order_id
    );

    v_expected_reserved := 200.0000000000;

    IF v_buy_order_id IS NULL THEN
        RAISE EXCEPTION 'Teste BUY com saldo suficiente falhou: order_id nao retornado';
    END IF;

    PERFORM 1
    FROM orders
    WHERE order_id = v_buy_order_id
      AND status = 'OPEN'
      AND quantity = 2.0000000000
      AND remaining_quantity = 2.0000000000
      AND reserved_amount = v_expected_reserved;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Teste BUY com saldo suficiente falhou: ordem nao foi criada corretamente';
    END IF;

    SELECT
        available_balance,
        locked_balance
    INTO
        v_after_quote_available,
        v_after_quote_locked
    FROM wallets
    WHERE user_id = v_buyer_user_id
      AND asset_id = v_quote_asset_id;

    IF v_after_quote_available <> v_initial_quote_available - v_expected_reserved
       OR v_after_quote_locked <> v_initial_quote_locked + v_expected_reserved THEN
        RAISE EXCEPTION 'Teste BUY com saldo suficiente falhou: saldo quote incorreto';
    END IF;

    RAISE NOTICE 'Teste aprovado: BUY com saldo suficiente criou ordem e bloqueou quote asset';

    SELECT
        available_balance,
        locked_balance
    INTO
        v_initial_base_available,
        v_initial_base_locked
    FROM wallets
    WHERE user_id = v_seller_user_id
      AND asset_id = v_base_asset_id;

    v_sell_order_id := NULL;
    CALL sp_place_order(
        v_seller_user_id,
        'BTC/USDT',
        'SELL'::enum_order_side,
        120.0000000000,
        1.0000000000,
        v_sell_order_id
    );

    IF v_sell_order_id IS NULL THEN
        RAISE EXCEPTION 'Teste SELL com saldo suficiente falhou: order_id nao retornado';
    END IF;

    PERFORM 1
    FROM orders
    WHERE order_id = v_sell_order_id
      AND status = 'OPEN'
      AND quantity = 1.0000000000
      AND remaining_quantity = 1.0000000000
      AND reserved_amount = 1.0000000000;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Teste SELL com saldo suficiente falhou: ordem nao foi criada corretamente';
    END IF;

    SELECT
        available_balance,
        locked_balance
    INTO
        v_after_base_available,
        v_after_base_locked
    FROM wallets
    WHERE user_id = v_seller_user_id
      AND asset_id = v_base_asset_id;

    IF v_after_base_available <> v_initial_base_available - 1.0000000000
       OR v_after_base_locked <> v_initial_base_locked + 1.0000000000 THEN
        RAISE EXCEPTION 'Teste SELL com saldo suficiente falhou: saldo base incorreto';
    END IF;

    RAISE NOTICE 'Teste aprovado: SELL com saldo suficiente criou ordem e bloqueou base asset';

    BEGIN
        CALL sp_place_order(
            v_poor_buyer_user_id,
            'BTC/USDT',
            'BUY'::enum_order_side,
            100.0000000000,
            1.0000000000,
            v_buy_order_id
        );

        RAISE EXCEPTION 'Teste BUY sem saldo falhou: a ordem foi aceita indevidamente';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'Teste BUY sem saldo falhou: a ordem foi aceita indevidamente' THEN
                RAISE;
            END IF;

            RAISE NOTICE 'Teste aprovado: BUY sem saldo falhou como esperado. Mensagem: %', SQLERRM;
    END;

    BEGIN
        CALL sp_place_order(
            v_poor_seller_user_id,
            'BTC/USDT',
            'SELL'::enum_order_side,
            120.0000000000,
            1.0000000000,
            v_sell_order_id
        );

        RAISE EXCEPTION 'Teste SELL sem saldo falhou: a ordem foi aceita indevidamente';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'Teste SELL sem saldo falhou: a ordem foi aceita indevidamente' THEN
                RAISE;
            END IF;

            RAISE NOTICE 'Teste aprovado: SELL sem saldo falhou como esperado. Mensagem: %', SQLERRM;
    END;

    SELECT
        available_balance,
        locked_balance
    INTO
        v_initial_quote_available,
        v_initial_quote_locked
    FROM wallets
    WHERE user_id = v_buyer_user_id
      AND asset_id = v_quote_asset_id;

    v_cancel_order_id := NULL;
    CALL sp_place_order(
        v_buyer_user_id,
        'BTC/USDT',
        'BUY'::enum_order_side,
        50.0000000000,
        1.0000000000,
        v_cancel_order_id
    );

    CALL sp_cancel_order(v_buyer_user_id, v_cancel_order_id);

    PERFORM 1
    FROM orders
    WHERE order_id = v_cancel_order_id
      AND status = 'CANCELED'
      AND remaining_quantity = 1.0000000000
      AND reserved_amount = 0.0000000000;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Teste cancelar ordem OPEN falhou: ordem nao ficou CANCELED com reserva zerada';
    END IF;

    SELECT
        available_balance,
        locked_balance
    INTO
        v_after_quote_available,
        v_after_quote_locked
    FROM wallets
    WHERE user_id = v_buyer_user_id
      AND asset_id = v_quote_asset_id;

    IF v_after_quote_available <> v_initial_quote_available
       OR v_after_quote_locked <> v_initial_quote_locked THEN
        RAISE EXCEPTION 'Teste cancelar ordem OPEN falhou: saldo nao foi liberado corretamente';
    END IF;

    RAISE NOTICE 'Teste aprovado: cancelamento de ordem OPEN liberou saldo e preservou remaining_quantity';

    v_other_cancel_order_id := NULL;
    CALL sp_place_order(
        v_seller_user_id,
        'BTC/USDT',
        'SELL'::enum_order_side,
        120.0000000000,
        0.5000000000,
        v_other_cancel_order_id
    );

    BEGIN
        CALL sp_cancel_order(v_other_user_id, v_other_cancel_order_id);

        RAISE EXCEPTION 'Teste outro usuario cancelando falhou: cancelamento foi aceito indevidamente';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'Teste outro usuario cancelando falhou: cancelamento foi aceito indevidamente' THEN
                RAISE;
            END IF;

            RAISE NOTICE 'Teste aprovado: outro usuario nao conseguiu cancelar ordem. Mensagem: %', SQLERRM;
    END;

    SELECT COUNT(*)
    INTO v_count
    FROM wallet_movements
    WHERE order_id IN (
        v_buy_order_id,
        v_sell_order_id,
        v_cancel_order_id,
        v_other_cancel_order_id
    )
      AND movement_type IN ('ORDER_LOCK', 'CANCEL_RELEASE');

    IF v_count < 5 THEN
        RAISE EXCEPTION 'Validacao de wallet_movements falhou: esperado ao menos 5 movimentos, encontrado %', v_count;
    END IF;

    RAISE NOTICE 'Teste aprovado: wallet_movements preenchida para ordens e cancelamento';

    SELECT COUNT(*)
    INTO v_count
    FROM order_audit_log
    WHERE order_id IN (
        v_buy_order_id,
        v_sell_order_id,
        v_cancel_order_id,
        v_other_cancel_order_id
    )
      AND event_type IN ('ORDER_CREATED', 'ORDER_CANCELED');

    IF v_count < 5 THEN
        RAISE EXCEPTION 'Validacao de order_audit_log falhou: esperado ao menos 5 registros, encontrado %', v_count;
    END IF;

    RAISE NOTICE 'Teste aprovado: order_audit_log preenchida para ordens e cancelamento';

    SELECT COUNT(*)
    INTO v_count
    FROM wallets
    WHERE available_balance < 0
       OR locked_balance < 0;

    IF v_count > 0 THEN
        RAISE EXCEPTION 'Validacao de saldos negativos falhou: % wallets com saldo negativo', v_count;
    END IF;

    RAISE NOTICE 'Teste aprovado: nenhuma wallet ficou com saldo negativo';
    RAISE NOTICE 'Validacao da migration 007 concluida com sucesso';
END;
$$;

ALTER TABLE orders ENABLE TRIGGER trg_match_order_after_insert;

ROLLBACK;
