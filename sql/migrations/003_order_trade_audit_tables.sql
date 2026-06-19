CREATE TABLE orders (
    order_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    market_id INTEGER NOT NULL REFERENCES markets(market_id) ON DELETE RESTRICT,
    side enum_order_side NOT NULL,
    price NUMERIC(28,10) NOT NULL,
    quantity NUMERIC(28,10) NOT NULL,
    remaining_quantity NUMERIC(28,10) NOT NULL,
    reserved_amount NUMERIC(28,10) NOT NULL DEFAULT 0,
    status enum_order_status NOT NULL DEFAULT 'OPEN',
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT chk_orders_price_positive CHECK (price > 0),
    CONSTRAINT chk_orders_quantity_positive CHECK (quantity > 0),
    CONSTRAINT chk_orders_remaining_non_negative CHECK (remaining_quantity >= 0),
    CONSTRAINT chk_orders_remaining_lte_quantity CHECK (remaining_quantity <= quantity),
    CONSTRAINT chk_orders_reserved_amount_non_negative CHECK (reserved_amount >= 0)
);

CREATE TABLE trades (
    trade_id BIGSERIAL PRIMARY KEY,
    market_id INTEGER NOT NULL REFERENCES markets(market_id) ON DELETE RESTRICT,
    buy_order_id BIGINT NOT NULL REFERENCES orders(order_id) ON DELETE RESTRICT,
    sell_order_id BIGINT NOT NULL REFERENCES orders(order_id) ON DELETE RESTRICT,
    buyer_user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    seller_user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    price NUMERIC(28,10) NOT NULL,
    quantity NUMERIC(28,10) NOT NULL,
    quote_amount NUMERIC(28,10) GENERATED ALWAYS AS (price * quantity) STORED,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT chk_trades_price_positive CHECK (price > 0),
    CONSTRAINT chk_trades_quantity_positive CHECK (quantity > 0),
    CONSTRAINT chk_trades_distinct_orders CHECK (buy_order_id <> sell_order_id),
    CONSTRAINT chk_trades_distinct_users CHECK (buyer_user_id <> seller_user_id)
);

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

CREATE TABLE order_audit_log (
    audit_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(order_id) ON DELETE RESTRICT,
    trade_id BIGINT NULL REFERENCES trades(trade_id) ON DELETE RESTRICT,
    old_status enum_order_status NULL,
    new_status enum_order_status NOT NULL,
    old_remaining_quantity NUMERIC(28,10) NULL,
    new_remaining_quantity NUMERIC(28,10) NOT NULL,
    event_type VARCHAR(30) NOT NULL,
    reason TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT chk_order_audit_event_type_not_empty CHECK (trim(event_type) <> ''),
    CONSTRAINT chk_order_audit_old_remaining_non_negative CHECK (old_remaining_quantity IS NULL OR old_remaining_quantity >= 0),
    CONSTRAINT chk_order_audit_new_remaining_non_negative CHECK (new_remaining_quantity >= 0)
);
