CREATE TABLE markets (
    market_id SERIAL PRIMARY KEY,
    base_asset_id INTEGER NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    quote_asset_id INTEGER NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    symbol VARCHAR(20) NOT NULL,
    min_order_quantity NUMERIC(28,10) NOT NULL DEFAULT 0.00000001,
    price_tick NUMERIC(28,10) NOT NULL DEFAULT 0.01,
    quantity_step NUMERIC(28,10) NOT NULL DEFAULT 0.00000001,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT uq_markets_symbol
        UNIQUE (symbol),

    CONSTRAINT uq_markets_pair
        UNIQUE (base_asset_id, quote_asset_id),

    CONSTRAINT chk_markets_symbol_not_empty
        CHECK (trim(symbol) <> ''),

    CONSTRAINT chk_markets_distinct_assets
        CHECK (base_asset_id <> quote_asset_id),

    CONSTRAINT chk_markets_min_order_quantity
        CHECK (min_order_quantity > 0),

    CONSTRAINT chk_markets_price_tick
        CHECK (price_tick > 0),

    CONSTRAINT chk_markets_quantity_step
        CHECK (quantity_step > 0)
);
