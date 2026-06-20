CREATE OR REPLACE VIEW view_market_summary AS
WITH last_trade AS (
    SELECT DISTINCT ON (t.market_id)
        t.market_id,
        t.price AS last_price
    FROM trades t
    ORDER BY t.market_id, t.executed_at DESC
),
price_reference AS (
    SELECT DISTINCT ON (t.market_id)
        t.market_id,
        t.price AS price_24h_ago
    FROM trades t
    WHERE t.executed_at <= clock_timestamp() - INTERVAL '24 hours'
    ORDER BY t.market_id, t.executed_at DESC
),
volume_24h AS (
    SELECT t.market_id,
           SUM(t.quantity) AS volume_24h_base,
           SUM(t.quote_amount) AS volume_24h_quote,
           COUNT(*) AS trades_24h
    FROM trades t
    WHERE t.executed_at >= clock_timestamp() - INTERVAL '24 hours'
    GROUP BY t.market_id
),
top_bid AS (
    SELECT o.market_id, MAX(o.price) AS best_bid
    FROM orders o
    WHERE o.side = 'BUY' AND o.status IN ('OPEN', 'PARTIAL')
    GROUP BY o.market_id
),
top_ask AS (
    SELECT o.market_id, MIN(o.price) AS best_ask
    FROM orders o
    WHERE o.side = 'SELL' AND o.status IN ('OPEN', 'PARTIAL')
    GROUP BY o.market_id
)
SELECT
    m.market_id,
    m.symbol,
    lt.last_price,
    pr.price_24h_ago,
    CASE
        WHEN pr.price_24h_ago IS NOT NULL AND pr.price_24h_ago <> 0
        THEN ((lt.last_price - pr.price_24h_ago) / pr.price_24h_ago) * 100
        ELSE NULL
    END AS variation_24h_percent,
    COALESCE(v.volume_24h_base, 0) AS volume_24h_base,
    COALESCE(v.volume_24h_quote, 0) AS volume_24h_quote,
    tb.best_bid,
    ta.best_ask,
    (ta.best_ask - tb.best_bid) AS spread,
    COALESCE(v.trades_24h, 0) AS trades_24h
FROM markets m
LEFT JOIN last_trade lt ON lt.market_id = m.market_id
LEFT JOIN price_reference pr ON pr.market_id = m.market_id
LEFT JOIN volume_24h v ON v.market_id = m.market_id
LEFT JOIN top_bid tb ON tb.market_id = m.market_id
LEFT JOIN top_ask ta ON ta.market_id = m.market_id;
