\echo 'Validacao de candles_1m apos INSERT em trades'

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
    v_buyer_id BIGINT;
    v_seller_id BIGINT;
    v_buy_order_id BIGINT;
    v_sell_order_id BIGINT;
    v_trade_id BIGINT;
    v_trade_bucket TIMESTAMPTZ;
    v_open_price NUMERIC(28,10);
    v_high_price NUMERIC(28,10);
    v_low_price NUMERIC(28,10);
    v_close_price NUMERIC(28,10);
    v_volume_base NUMERIC(28,10);
    v_volume_quote NUMERIC(28,10);
    v_trades_count INTEGER;
BEGIN
    v_base_symbol := ('CB' || v_suffix)::VARCHAR(10);
    v_quote_symbol := ('CQ' || v_suffix)::VARCHAR(10);
    v_market_symbol := (v_base_symbol || '/' || v_quote_symbol)::VARCHAR(20);

    INSERT INTO assets (symbol, name, decimal_places, is_active)
    VALUES
        (v_base_symbol, 'Base candles validation', 8, true),
        (v_quote_symbol, 'Quote candles validation', 2, true);

    SELECT asset_id
    INTO v_base_id
    FROM assets
    WHERE symbol = v_base_symbol;

    SELECT asset_id
    INTO v_quote_id
    FROM assets
    WHERE symbol = v_quote_symbol;

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
        v_base_id,
        v_quote_id,
        v_market_symbol,
        0.0000000100,
        0.0100000000,
        0.0000000100,
        true
    )
    RETURNING market_id INTO v_market_id;

    INSERT INTO users (name, email, is_active)
    VALUES ('Comprador candles', 'candles-buyer-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_buyer_id;

    INSERT INTO users (name, email, is_active)
    VALUES ('Vendedor candles', 'candles-seller-' || v_suffix || '@example.com', true)
    RETURNING user_id INTO v_seller_id;

    INSERT INTO wallets (user_id, asset_id, available_balance, locked_balance)
    VALUES
        (v_buyer_id, v_base_id, 0, 0),
        (v_buyer_id, v_quote_id, 0, 0),
        (v_seller_id, v_base_id, 0, 0),
        (v_seller_id, v_quote_id, 0, 0);

    CALL sp_deposit(v_buyer_id, v_quote_symbol, 10000, 'Saldo validacao candles');
    CALL sp_deposit(v_seller_id, v_base_symbol, 100, 'Saldo validacao candles');

    CALL sp_place_order(
        v_seller_id,
        v_market_symbol,
        'SELL'::enum_order_side,
        100,
        2,
        v_sell_order_id
    );

    CALL sp_place_order(
        v_buyer_id,
        v_market_symbol,
        'BUY'::enum_order_side,
        100,
        2,
        v_buy_order_id
    );

    SELECT
        trade_id,
        date_trunc('minute', executed_at)
    INTO
        v_trade_id,
        v_trade_bucket
    FROM trades
    WHERE buy_order_id = v_buy_order_id
      AND sell_order_id = v_sell_order_id;

    ASSERT v_trade_id IS NOT NULL,
        'candles_1m: matching automatico deveria criar um trade';

    SELECT
        open_price,
        high_price,
        low_price,
        close_price,
        volume_base,
        volume_quote,
        trades_count
    INTO
        v_open_price,
        v_high_price,
        v_low_price,
        v_close_price,
        v_volume_base,
        v_volume_quote,
        v_trades_count
    FROM candles_1m
    WHERE market_id = v_market_id
      AND bucket_minute = v_trade_bucket;

    ASSERT FOUND,
        'candles_1m: deveria existir candle para o minuto do trade';

    ASSERT v_volume_base > 0,
        'candles_1m: volume_base deveria ser maior que zero';

    ASSERT v_volume_quote > 0,
        'candles_1m: volume_quote deveria ser maior que zero';

    ASSERT v_trades_count > 0,
        'candles_1m: trades_count deveria ser maior que zero';

    ASSERT v_open_price > 0
       AND v_high_price > 0
       AND v_low_price > 0
       AND v_close_price > 0,
        'candles_1m: OHLC deveria estar preenchido com valores positivos';

    RAISE NOTICE 'Validacao de candles_1m concluida com sucesso';
END;
$$;

ROLLBACK;
