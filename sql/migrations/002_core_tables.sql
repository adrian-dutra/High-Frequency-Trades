CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    email VARCHAR(160) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT chk_users_name_not_empty
        CHECK (trim(name) <> ''),

    CONSTRAINT chk_users_email_not_empty
        CHECK (trim(email) <> ''),

    CONSTRAINT uq_users_email
        UNIQUE (email)
);

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

CREATE TABLE wallets (
    wallet_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    asset_id INTEGER NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    available_balance NUMERIC(28,10) NOT NULL DEFAULT 0,
    locked_balance NUMERIC(28,10) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT uq_wallets_user_asset
        UNIQUE (user_id, asset_id),

    CONSTRAINT chk_wallets_available_non_negative
        CHECK (available_balance >= 0),

    CONSTRAINT chk_wallets_locked_non_negative
        CHECK (locked_balance >= 0)
);
