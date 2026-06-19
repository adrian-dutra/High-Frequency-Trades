CREATE TABLE candles_1m (
    market_id INTEGER NOT NULL REFERENCES markets(market_id) ON DELETE RESTRICT,
    bucket_minute TIMESTAMPTZ NOT NULL,
    open_price NUMERIC(28,10) NOT NULL,
    high_price NUMERIC(28,10) NOT NULL,
    low_price NUMERIC(28,10) NOT NULL,
    close_price NUMERIC(28,10) NOT NULL,
    volume_base NUMERIC(28,10) NOT NULL DEFAULT 0,
    volume_quote NUMERIC(28,10) NOT NULL DEFAULT 0,
    trades_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    PRIMARY KEY (market_id, bucket_minute),

    CONSTRAINT chk_candles_open_price_positive CHECK (open_price > 0),
    CONSTRAINT chk_candles_high_price_positive CHECK (high_price > 0),
    CONSTRAINT chk_candles_low_price_positive CHECK (low_price > 0),
    CONSTRAINT chk_candles_close_price_positive CHECK (close_price > 0),
    CONSTRAINT chk_candles_high_gte_low CHECK (high_price >= low_price),
    CONSTRAINT chk_candles_volume_base_non_negative CHECK (volume_base >= 0),
    CONSTRAINT chk_candles_volume_quote_non_negative CHECK (volume_quote >= 0),
    CONSTRAINT chk_candles_trades_count_non_negative CHECK (trades_count >= 0)
) PARTITION BY RANGE (bucket_minute);

CREATE TABLE candles_1m_2026_01
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');

CREATE TABLE candles_1m_2026_02
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');

CREATE TABLE candles_1m_2026_03
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-03-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');

CREATE TABLE candles_1m_2026_04
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');

CREATE TABLE candles_1m_2026_05
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');

CREATE TABLE candles_1m_2026_06
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE candles_1m_2026_07
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');

CREATE TABLE candles_1m_2026_08
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');

CREATE TABLE candles_1m_2026_09
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE candles_1m_2026_10
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');

CREATE TABLE candles_1m_2026_11
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');

CREATE TABLE candles_1m_2026_12
    PARTITION OF candles_1m
    FOR VALUES FROM ('2026-12-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');
