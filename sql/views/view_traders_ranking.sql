CREATE OR REPLACE VIEW view_traders_ranking AS
WITH trader_activity AS (
    SELECT t.buyer_user_id AS user_id, t.quote_amount
    FROM trades t
    WHERE t.executed_at >= clock_timestamp() - INTERVAL '24 hours'
    UNION ALL
    SELECT t.seller_user_id AS user_id, t.quote_amount
    FROM trades t
    WHERE t.executed_at >= clock_timestamp() - INTERVAL '24 hours'
),
trader_volume AS (
    SELECT u.user_id,
           u.name,
           SUM(ta.quote_amount) AS total_volume_quote,
           COUNT(*) AS total_trades
    FROM trader_activity ta
    JOIN users u ON u.user_id = ta.user_id
    GROUP BY u.user_id, u.name
)
SELECT
    RANK() OVER (ORDER BY total_volume_quote DESC) AS rank_position,
    user_id,
    name,
    total_volume_quote,
    total_trades
FROM trader_volume;
