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
