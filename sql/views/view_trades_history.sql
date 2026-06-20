CREATE OR REPLACE VIEW view_trades_history AS
SELECT
    t.trade_id,
    m.symbol AS market_symbol,
    t.price,
    t.quantity,
    t.quote_amount,
    t.buyer_user_id,
    bu.name AS buyer_name,
    t.seller_user_id,
    su.name AS seller_name,
    t.executed_at
FROM trades t
JOIN markets m ON m.market_id = t.market_id
JOIN users bu ON bu.user_id = t.buyer_user_id
JOIN users su ON su.user_id = t.seller_user_id
ORDER BY t.executed_at DESC;
