CREATE OR REPLACE FUNCTION get_best_orders(
    p_market_id INTEGER,
    p_depth INTEGER DEFAULT 10
)
RETURNS TABLE (
    side enum_order_side,
    price NUMERIC(28,10),
    available_quantity NUMERIC(28,10),
    orders_count BIGINT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    (
        SELECT o.side,
               o.price,
               SUM(o.remaining_quantity)::NUMERIC(28,10),
               COUNT(*)::BIGINT
        FROM orders o
        WHERE o.market_id = p_market_id
          AND o.side = 'BUY'
          AND o.status IN ('OPEN', 'PARTIAL')
        GROUP BY o.side, o.price
        ORDER BY o.price DESC
        LIMIT p_depth
    )
    UNION ALL
    (
        SELECT o.side,
               o.price,
               SUM(o.remaining_quantity)::NUMERIC(28,10),
               COUNT(*)::BIGINT
        FROM orders o
        WHERE o.market_id = p_market_id
          AND o.side = 'SELL'
          AND o.status IN ('OPEN', 'PARTIAL')
        GROUP BY o.side, o.price
        ORDER BY o.price ASC
        LIMIT p_depth
    );
END;
$$;
