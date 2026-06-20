CREATE INDEX idx_orders_open_buy_book
ON orders (market_id, price DESC, created_at ASC, order_id ASC)
WHERE side = 'BUY' AND status IN ('OPEN', 'PARTIAL');

CREATE INDEX idx_orders_open_sell_book
ON orders (market_id, price ASC, created_at ASC, order_id ASC)
WHERE side = 'SELL' AND status IN ('OPEN', 'PARTIAL');

CREATE INDEX idx_trades_market_executed_at
ON trades (market_id, executed_at DESC);

CREATE INDEX idx_order_audit_order_created
ON order_audit_log (order_id, created_at DESC);

CREATE INDEX idx_wallet_movements_wallet_created
ON wallet_movements (wallet_id, created_at DESC);

CREATE INDEX idx_candles_1m_market_bucket_desc
ON candles_1m (market_id, bucket_minute DESC);
