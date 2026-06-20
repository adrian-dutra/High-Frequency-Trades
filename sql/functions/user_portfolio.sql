CREATE OR REPLACE FUNCTION user_portfolio(p_user_id BIGINT)
RETURNS TABLE (
    asset_symbol VARCHAR,
    available_balance NUMERIC(28,10),
    locked_balance NUMERIC(28,10),
    total_balance NUMERIC(28,10),
    last_price_usdt NUMERIC(28,10),
    estimated_value_usdt NUMERIC(28,10)
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.symbol,
        w.available_balance,
        w.locked_balance,
        (w.available_balance + w.locked_balance)::NUMERIC(28,10),
        lp.price,
        ((w.available_balance + w.locked_balance) * lp.price)::NUMERIC(28,10)
    FROM wallets w
    JOIN assets a ON a.asset_id = w.asset_id
    LEFT JOIN LATERAL (
        SELECT CASE
                   WHEN a.symbol = 'USDT' THEN 1::NUMERIC(28,10)
                   ELSE (
                       SELECT t.price
                       FROM trades t
                       JOIN markets m ON m.market_id = t.market_id
                       JOIN assets q ON q.asset_id = m.quote_asset_id
                       WHERE m.base_asset_id = w.asset_id
                         AND q.symbol = 'USDT'
                       ORDER BY t.executed_at DESC
                       LIMIT 1
                   )
               END AS price
    ) lp ON true
    WHERE w.user_id = p_user_id
    ORDER BY a.symbol;
END;
$$;
