\echo 'Validacao do fluxo completo (Pessoa B): matching, partial fill, cancelamento, imutabilidade, funcoes e views'

BEGIN;

DO $$
DECLARE
    v_suffix TEXT := substring(md5(clock_timestamp()::TEXT || txid_current()::TEXT), 1, 4);
    v_base_symbol VARCHAR(10);
    v_quote_symbol VARCHAR(10);
    v_market_symbol VARCHAR(20);
    v_base_id INTEGER;
    v_quote_id INTEGER;
    v_market_id INTEGER;
    v_buyer BIGINT;
    v_seller BIGINT;
    v_poor BIGINT;
    v_buy_order BIGINT;
    v_sell_order BIGINT;
    v_partial_sell BIGINT;
    v_extra_buy BIGINT;
    v_throwaway BIGINT;
    v_trade_count INTEGER;
    v_status enum_order_status;
    v_remaining NUMERIC(28,10);
    v_reserved NUMERIC(28,10);
    v_value NUMERIC(28,10);
    v_locked NUMERIC(28,10);
    v_best_qty NUMERIC(28,10);
    v_best_count BIGINT;
    v_count INTEGER;
    v_rank BIGINT;
    v_failed BOOLEAN;
BEGIN
    v_base_symbol := ('VB' || v_suffix)::VARCHAR(10);
    v_quote_symbol := ('VQ' || v_suffix)::VARCHAR(10);
    v_market_symbol := (v_base_symbol || '/' || v_quote_symbol)::VARCHAR(20);

    INSERT INTO assets (symbol, name, decimal_places, is_active)
    VALUES (v_base_symbol, 'Base fluxo B', 8, true),
           (v_quote_symbol, 'Quote fluxo B', 2, true);

    SELECT asset_id INTO v_base_id FROM assets WHERE symbol = v_base_symbol;
    SELECT asset_id INTO v_quote_id FROM assets WHERE symbol = v_quote_symbol;

    INSERT INTO markets (base_asset_id, quote_asset_id, symbol, min_order_quantity, price_tick, quantity_step, is_active)
    VALUES (v_base_id, v_quote_id, v_market_symbol, 0.0000000100, 0.0100000000, 0.0000000100, true)
    RETURNING market_id INTO v_market_id;

    INSERT INTO users (name, email, is_active)
    VALUES ('Comprador fluxo B', 'fluxo-b-buyer-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_buyer;

    INSERT INTO users (name, email, is_active)
    VALUES ('Vendedor fluxo B', 'fluxo-b-seller-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_seller;

    INSERT INTO users (name, email, is_active)
    VALUES ('Sem saldo fluxo B', 'fluxo-b-poor-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_poor;

    INSERT INTO wallets (user_id, asset_id, available_balance, locked_balance)
    VALUES (v_buyer, v_base_id, 0, 0),
           (v_buyer, v_quote_id, 0, 0),
           (v_seller, v_base_id, 0, 0),
           (v_seller, v_quote_id, 0, 0),
           (v_poor, v_base_id, 0, 0),
           (v_poor, v_quote_id, 0, 0);

    CALL sp_deposit(v_buyer, v_quote_symbol, 1000000, 'Saldo teste fluxo B');
    CALL sp_deposit(v_seller, v_base_symbol, 1000, 'Saldo teste fluxo B');

    CALL sp_place_order(v_seller, v_market_symbol, 'SELL'::enum_order_side, 100, 2, v_sell_order);
    CALL sp_place_order(v_buyer, v_market_symbol, 'BUY'::enum_order_side, 100, 2, v_buy_order);

    SELECT COUNT(*) INTO v_trade_count
    FROM trades
    WHERE buy_order_id = v_buy_order AND sell_order_id = v_sell_order;
    ASSERT v_trade_count = 1, 'matching total: deveria existir exatamente 1 trade';

    SELECT status, remaining_quantity, reserved_amount INTO v_status, v_remaining, v_reserved
    FROM orders WHERE order_id = v_buy_order;
    ASSERT v_status = 'FILLED' AND v_remaining = 0 AND v_reserved = 0,
        'matching total: ordem BUY deveria ficar FILLED zerada';

    SELECT status, remaining_quantity, reserved_amount INTO v_status, v_remaining, v_reserved
    FROM orders WHERE order_id = v_sell_order;
    ASSERT v_status = 'FILLED' AND v_remaining = 0 AND v_reserved = 0,
        'matching total: ordem SELL deveria ficar FILLED zerada';

    SELECT available_balance INTO v_value
    FROM wallets WHERE user_id = v_buyer AND asset_id = v_base_id;
    ASSERT v_value = 2, 'saldo: comprador deveria receber 2 do ativo base';

    SELECT available_balance, locked_balance INTO v_value, v_locked
    FROM wallets WHERE user_id = v_buyer AND asset_id = v_quote_id;
    ASSERT v_value = 999800 AND v_locked = 0,
        'saldo: comprador deveria pagar 200 de quote e nao manter bloqueio';

    SELECT available_balance, locked_balance INTO v_value, v_locked
    FROM wallets WHERE user_id = v_seller AND asset_id = v_base_id;
    ASSERT v_value = 998 AND v_locked = 0,
        'saldo: vendedor deveria entregar 2 do ativo base sem bloqueio residual';

    SELECT available_balance INTO v_value
    FROM wallets WHERE user_id = v_seller AND asset_id = v_quote_id;
    ASSERT v_value = 200, 'saldo: vendedor deveria receber 200 de quote';

    SELECT COUNT(*) INTO v_count
    FROM wallet_movements wm
    JOIN trades t ON t.trade_id = wm.trade_id
    WHERE t.buy_order_id = v_buy_order
      AND wm.movement_type IN ('TRADE_DEBIT', 'TRADE_CREDIT');
    ASSERT v_count >= 4, 'auditoria: trade deveria gerar movimentos de debito e credito';

    SELECT COUNT(*) INTO v_count
    FROM order_audit_log
    WHERE order_id IN (v_buy_order, v_sell_order)
      AND event_type = 'ORDER_FILLED';
    ASSERT v_count = 2, 'auditoria: deveria registrar ORDER_FILLED para as duas ordens';

    CALL sp_place_order(v_seller, v_market_symbol, 'SELL'::enum_order_side, 100, 5, v_partial_sell);
    CALL sp_place_order(v_buyer, v_market_symbol, 'BUY'::enum_order_side, 100, 2, v_extra_buy);

    SELECT status, remaining_quantity, reserved_amount INTO v_status, v_remaining, v_reserved
    FROM orders WHERE order_id = v_partial_sell;
    ASSERT v_status = 'PARTIAL' AND v_remaining = 3 AND v_reserved = 3,
        'partial fill: SELL deveria ficar PARTIAL com 3 restantes e 3 reservados';

    SELECT available_quantity, orders_count INTO v_best_qty, v_best_count
    FROM get_best_orders(v_market_id, 10) WHERE side = 'SELL';
    ASSERT v_best_qty = 3 AND v_best_count = 1,
        'get_best_orders: book de venda deveria mostrar 3 disponiveis em 1 ordem';

    PERFORM cancel_order(v_seller, v_partial_sell);

    SELECT status, reserved_amount INTO v_status, v_reserved
    FROM orders WHERE order_id = v_partial_sell;
    ASSERT v_status = 'CANCELED' AND v_reserved = 0,
        'cancelamento: ordem deveria ficar CANCELED sem reserva';

    SELECT available_balance, locked_balance INTO v_value, v_locked
    FROM wallets WHERE user_id = v_seller AND asset_id = v_base_id;
    ASSERT v_value = 996 AND v_locked = 0,
        'cancelamento: saldo bloqueado restante deveria voltar para disponivel';

    v_failed := false;
    BEGIN
        CALL sp_place_order(v_poor, v_market_symbol, 'BUY'::enum_order_side, 100, 1, v_throwaway);
    EXCEPTION WHEN OTHERS THEN
        v_failed := true;
    END;
    ASSERT v_failed, 'saldo insuficiente: BUY sem quote deveria falhar';

    v_failed := false;
    BEGIN
        CALL sp_place_order(v_poor, v_market_symbol, 'SELL'::enum_order_side, 100, 1, v_throwaway);
    EXCEPTION WHEN OTHERS THEN
        v_failed := true;
    END;
    ASSERT v_failed, 'saldo insuficiente: SELL sem base deveria falhar';

    v_failed := false;
    BEGIN
        UPDATE trades SET price = price + 1 WHERE market_id = v_market_id;
    EXCEPTION WHEN OTHERS THEN
        v_failed := true;
    END;
    ASSERT v_failed, 'imutabilidade: UPDATE em trades deveria falhar';

    v_failed := false;
    BEGIN
        DELETE FROM trades WHERE market_id = v_market_id;
    EXCEPTION WHEN OTHERS THEN
        v_failed := true;
    END;
    ASSERT v_failed, 'imutabilidade: DELETE em trades deveria falhar';

    SELECT total_balance INTO v_value
    FROM user_portfolio(v_buyer) WHERE asset_symbol = v_base_symbol;
    ASSERT v_value = 4, 'user_portfolio: total do ativo base do comprador deveria ser 4';

    SELECT last_price INTO v_value
    FROM view_market_summary WHERE market_id = v_market_id;
    ASSERT v_value = 100, 'view_market_summary: ultimo preco deveria ser 100';

    SELECT COUNT(*) INTO v_count
    FROM view_trades_history WHERE market_symbol = v_market_symbol;
    ASSERT v_count = 2, 'view_trades_history: deveria listar 2 trades do mercado';

    SELECT MIN(rank_position) INTO v_rank
    FROM view_traders_ranking WHERE user_id IN (v_buyer, v_seller);
    ASSERT v_rank = 1, 'view_traders_ranking: traders ativos deveriam alcancar o rank 1';

    RAISE NOTICE 'OK matching total e atualizacao de saldos';
    RAISE NOTICE 'OK partial fill e get_best_orders';
    RAISE NOTICE 'OK cancel_order liberando saldo bloqueado';
    RAISE NOTICE 'OK rejeicao de ordens sem saldo';
    RAISE NOTICE 'OK imutabilidade de trades';
    RAISE NOTICE 'OK user_portfolio e views com dados reais';
    RAISE NOTICE 'Fluxo completo da Pessoa B validado com sucesso';
END;
$$;

ROLLBACK;
