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
