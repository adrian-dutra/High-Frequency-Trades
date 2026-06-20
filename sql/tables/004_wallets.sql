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
