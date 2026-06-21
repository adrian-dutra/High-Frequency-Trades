\echo 'Totais da seed base'

SELECT 'assets' AS item, 5 AS expected_count, COUNT(*) AS actual_count
FROM assets
UNION ALL
SELECT 'markets' AS item, 3 AS expected_count, COUNT(*) AS actual_count
FROM markets
UNION ALL
SELECT 'users' AS item, 10 AS expected_count, COUNT(*) AS actual_count
FROM users
UNION ALL
SELECT 'wallets' AS item, 50 AS expected_count, COUNT(*) AS actual_count
FROM wallets
UNION ALL
SELECT 'wallet_movements_initial_deposit' AS item, 50 AS expected_count, COUNT(*) AS actual_count
FROM wallet_movements
WHERE movement_type = 'DEPOSIT'
  AND description = 'Initial seed deposit'
ORDER BY item;

\echo 'Carteiras duplicadas por usuario e ativo. Esperado: zero linhas.'

SELECT
    user_id,
    asset_id,
    COUNT(*) AS duplicate_count
FROM wallets
GROUP BY user_id, asset_id
HAVING COUNT(*) > 1
ORDER BY user_id, asset_id;

\echo 'Carteiras com saldos negativos. Esperado: zero linhas.'

SELECT
    wallet_id,
    user_id,
    asset_id,
    available_balance,
    locked_balance
FROM wallets
WHERE available_balance < 0
   OR locked_balance < 0
ORDER BY wallet_id;

\echo 'Carteiras positivas sem movimentacao inicial de deposito. Esperado: zero linhas.'

SELECT
    wallets.wallet_id,
    users.email,
    assets.symbol,
    wallets.available_balance
FROM wallets
JOIN users
    ON users.user_id = wallets.user_id
JOIN assets
    ON assets.asset_id = wallets.asset_id
WHERE wallets.available_balance > 0
  AND NOT EXISTS (
      SELECT 1
      FROM wallet_movements
      WHERE wallet_movements.wallet_id = wallets.wallet_id
        AND wallet_movements.movement_type = 'DEPOSIT'
        AND wallet_movements.description = 'Initial seed deposit'
  )
ORDER BY users.email, assets.symbol;

\echo 'Saldo disponivel por ativo'

SELECT
    assets.symbol,
    SUM(wallets.available_balance) AS total_available_balance
FROM wallets
JOIN assets
    ON assets.asset_id = wallets.asset_id
GROUP BY assets.symbol
ORDER BY assets.symbol;

\echo 'Usuarios da seed e quantidade de carteiras por usuario'

SELECT
    users.email,
    COUNT(wallets.wallet_id) AS wallets_count
FROM users
LEFT JOIN wallets
    ON wallets.user_id = users.user_id
GROUP BY users.email
ORDER BY users.email;
