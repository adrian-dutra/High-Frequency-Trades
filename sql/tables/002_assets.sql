CREATE TABLE assets (
    asset_id SERIAL PRIMARY KEY,
    symbol VARCHAR(10) NOT NULL,
    name VARCHAR(80) NOT NULL,
    decimal_places SMALLINT NOT NULL DEFAULT 8,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT uq_assets_symbol
        UNIQUE (symbol),

    CONSTRAINT chk_assets_symbol_not_empty
        CHECK (trim(symbol) <> ''),

    CONSTRAINT chk_assets_name_not_empty
        CHECK (trim(name) <> ''),

    CONSTRAINT chk_assets_decimal_places
        CHECK (decimal_places BETWEEN 0 AND 10)
);
