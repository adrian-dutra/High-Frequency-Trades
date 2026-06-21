CREATE OR REPLACE FUNCTION trg_update_candles_1m_after_trade_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bucket_minute TIMESTAMPTZ;
BEGIN
    v_bucket_minute := date_trunc('minute', NEW.executed_at);

    INSERT INTO candles_1m (
        market_id,
        bucket_minute,
        open_price,
        high_price,
        low_price,
        close_price,
        volume_base,
        volume_quote,
        trades_count
    )
    VALUES (
        NEW.market_id,
        v_bucket_minute,
        NEW.price,
        NEW.price,
        NEW.price,
        NEW.price,
        NEW.quantity,
        NEW.quote_amount,
        1
    )
    ON CONFLICT (market_id, bucket_minute) DO UPDATE
    SET
        high_price = GREATEST(candles_1m.high_price, NEW.price),
        low_price = LEAST(candles_1m.low_price, NEW.price),
        close_price = NEW.price,
        volume_base = candles_1m.volume_base + NEW.quantity,
        volume_quote = candles_1m.volume_quote + NEW.quote_amount,
        trades_count = candles_1m.trades_count + 1,
        updated_at = clock_timestamp();

    RETURN NEW;
END;
$$;
