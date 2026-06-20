CREATE TABLE wallet_movements (
    movement_id BIGSERIAL PRIMARY KEY,
    wallet_id BIGINT NOT NULL REFERENCES wallets(wallet_id) ON DELETE RESTRICT,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    asset_id INTEGER NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    order_id BIGINT NULL REFERENCES orders(order_id) ON DELETE RESTRICT,
    trade_id BIGINT NULL REFERENCES trades(trade_id) ON DELETE RESTRICT,
    movement_type enum_wallet_movement_type NOT NULL,
    amount NUMERIC(28,10) NOT NULL,
    available_balance_after NUMERIC(28,10) NOT NULL,
    locked_balance_after NUMERIC(28,10) NOT NULL,
    description TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT chk_wallet_movements_amount_not_zero CHECK (amount <> 0),
    CONSTRAINT chk_wallet_movements_available_balance_after_non_negative CHECK (available_balance_after >= 0),
    CONSTRAINT chk_wallet_movements_locked_balance_after_non_negative CHECK (locked_balance_after >= 0)
);
