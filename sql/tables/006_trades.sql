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
