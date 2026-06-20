INSERT INTO assets (symbol, name, decimal_places, is_active)
VALUES
    ('BTC', 'Bitcoin', 8, true),
    ('ETH', 'Ethereum', 8, true),
    ('SOL', 'Solana', 8, true),
    ('USDT', 'Tether USD', 2, true),
    ('BRL', 'Real Brasileiro', 2, true)
ON CONFLICT (symbol) DO UPDATE
SET
    name = EXCLUDED.name,
    decimal_places = EXCLUDED.decimal_places,
    is_active = EXCLUDED.is_active;

INSERT INTO markets (
    base_asset_id,
    quote_asset_id,
    symbol,
    min_order_quantity,
    price_tick,
    quantity_step,
    is_active
)
SELECT
    base.asset_id,
    quote.asset_id,
    market_data.symbol,
    market_data.min_order_quantity,
    market_data.price_tick,
    market_data.quantity_step,
    true
FROM (
    VALUES
        ('BTC/USDT', 'BTC', 'USDT', 0.0001000000::NUMERIC(28,10), 0.0100000000::NUMERIC(28,10), 0.0001000000::NUMERIC(28,10)),
        ('ETH/USDT', 'ETH', 'USDT', 0.0010000000::NUMERIC(28,10), 0.0100000000::NUMERIC(28,10), 0.0010000000::NUMERIC(28,10)),
        ('SOL/USDT', 'SOL', 'USDT', 0.0100000000::NUMERIC(28,10), 0.0100000000::NUMERIC(28,10), 0.0100000000::NUMERIC(28,10))
) AS market_data(symbol, base_symbol, quote_symbol, min_order_quantity, price_tick, quantity_step)
JOIN assets base
    ON base.symbol = market_data.base_symbol
JOIN assets quote
    ON quote.symbol = market_data.quote_symbol
ON CONFLICT (symbol) DO UPDATE
SET
    base_asset_id = EXCLUDED.base_asset_id,
    quote_asset_id = EXCLUDED.quote_asset_id,
    min_order_quantity = EXCLUDED.min_order_quantity,
    price_tick = EXCLUDED.price_tick,
    quantity_step = EXCLUDED.quantity_step,
    is_active = EXCLUDED.is_active;

INSERT INTO users (name, email, is_active)
VALUES
    ('Alice Silva', 'alice.seed@example.com', true),
    ('Bruno Costa', 'bruno.seed@example.com', true),
    ('Carla Mendes', 'carla.seed@example.com', true),
    ('Diego Rocha', 'diego.seed@example.com', true),
    ('Eduarda Lima', 'eduarda.seed@example.com', true),
    ('Felipe Santos', 'felipe.seed@example.com', true),
    ('Gabriela Alves', 'gabriela.seed@example.com', true),
    ('Henrique Souza', 'henrique.seed@example.com', true),
    ('Isabela Martins', 'isabela.seed@example.com', true),
    ('Joao Pereira', 'joao.seed@example.com', true)
ON CONFLICT (email) DO UPDATE
SET
    name = EXCLUDED.name,
    is_active = EXCLUDED.is_active;

WITH seed_balances (email, symbol, available_balance) AS (
    VALUES
        ('alice.seed@example.com', 'BTC', 0.2500000000::NUMERIC(28,10)),
        ('alice.seed@example.com', 'ETH', 4.0000000000::NUMERIC(28,10)),
        ('alice.seed@example.com', 'SOL', 300.0000000000::NUMERIC(28,10)),
        ('alice.seed@example.com', 'USDT', 250000.0000000000::NUMERIC(28,10)),
        ('alice.seed@example.com', 'BRL', 50000.0000000000::NUMERIC(28,10)),

        ('bruno.seed@example.com', 'BTC', 0.1800000000::NUMERIC(28,10)),
        ('bruno.seed@example.com', 'ETH', 3.5000000000::NUMERIC(28,10)),
        ('bruno.seed@example.com', 'SOL', 250.0000000000::NUMERIC(28,10)),
        ('bruno.seed@example.com', 'USDT', 180000.0000000000::NUMERIC(28,10)),
        ('bruno.seed@example.com', 'BRL', 35000.0000000000::NUMERIC(28,10)),

        ('carla.seed@example.com', 'BTC', 0.1200000000::NUMERIC(28,10)),
        ('carla.seed@example.com', 'ETH', 2.8000000000::NUMERIC(28,10)),
        ('carla.seed@example.com', 'SOL', 220.0000000000::NUMERIC(28,10)),
        ('carla.seed@example.com', 'USDT', 150000.0000000000::NUMERIC(28,10)),
        ('carla.seed@example.com', 'BRL', 30000.0000000000::NUMERIC(28,10)),

        ('diego.seed@example.com', 'BTC', 0.1000000000::NUMERIC(28,10)),
        ('diego.seed@example.com', 'ETH', 2.0000000000::NUMERIC(28,10)),
        ('diego.seed@example.com', 'SOL', 180.0000000000::NUMERIC(28,10)),
        ('diego.seed@example.com', 'USDT', 120000.0000000000::NUMERIC(28,10)),
        ('diego.seed@example.com', 'BRL', 25000.0000000000::NUMERIC(28,10)),

        ('eduarda.seed@example.com', 'BTC', 0.0800000000::NUMERIC(28,10)),
        ('eduarda.seed@example.com', 'ETH', 1.5000000000::NUMERIC(28,10)),
        ('eduarda.seed@example.com', 'SOL', 150.0000000000::NUMERIC(28,10)),
        ('eduarda.seed@example.com', 'USDT', 90000.0000000000::NUMERIC(28,10)),
        ('eduarda.seed@example.com', 'BRL', 20000.0000000000::NUMERIC(28,10)),

        ('felipe.seed@example.com', 'BTC', 1.5000000000::NUMERIC(28,10)),
        ('felipe.seed@example.com', 'ETH', 18.0000000000::NUMERIC(28,10)),
        ('felipe.seed@example.com', 'SOL', 1200.0000000000::NUMERIC(28,10)),
        ('felipe.seed@example.com', 'USDT', 50000.0000000000::NUMERIC(28,10)),
        ('felipe.seed@example.com', 'BRL', 18000.0000000000::NUMERIC(28,10)),

        ('gabriela.seed@example.com', 'BTC', 1.2000000000::NUMERIC(28,10)),
        ('gabriela.seed@example.com', 'ETH', 14.0000000000::NUMERIC(28,10)),
        ('gabriela.seed@example.com', 'SOL', 1000.0000000000::NUMERIC(28,10)),
        ('gabriela.seed@example.com', 'USDT', 45000.0000000000::NUMERIC(28,10)),
        ('gabriela.seed@example.com', 'BRL', 16000.0000000000::NUMERIC(28,10)),

        ('henrique.seed@example.com', 'BTC', 0.9500000000::NUMERIC(28,10)),
        ('henrique.seed@example.com', 'ETH', 11.0000000000::NUMERIC(28,10)),
        ('henrique.seed@example.com', 'SOL', 850.0000000000::NUMERIC(28,10)),
        ('henrique.seed@example.com', 'USDT', 40000.0000000000::NUMERIC(28,10)),
        ('henrique.seed@example.com', 'BRL', 14000.0000000000::NUMERIC(28,10)),

        ('isabela.seed@example.com', 'BTC', 0.7000000000::NUMERIC(28,10)),
        ('isabela.seed@example.com', 'ETH', 8.0000000000::NUMERIC(28,10)),
        ('isabela.seed@example.com', 'SOL', 650.0000000000::NUMERIC(28,10)),
        ('isabela.seed@example.com', 'USDT', 35000.0000000000::NUMERIC(28,10)),
        ('isabela.seed@example.com', 'BRL', 12000.0000000000::NUMERIC(28,10)),

        ('joao.seed@example.com', 'BTC', 0.5500000000::NUMERIC(28,10)),
        ('joao.seed@example.com', 'ETH', 6.5000000000::NUMERIC(28,10)),
        ('joao.seed@example.com', 'SOL', 500.0000000000::NUMERIC(28,10)),
        ('joao.seed@example.com', 'USDT', 30000.0000000000::NUMERIC(28,10)),
        ('joao.seed@example.com', 'BRL', 10000.0000000000::NUMERIC(28,10))
)
INSERT INTO wallets (
    user_id,
    asset_id,
    available_balance,
    locked_balance
)
SELECT
    users.user_id,
    assets.asset_id,
    seed_balances.available_balance,
    0::NUMERIC(28,10)
FROM seed_balances
JOIN users
    ON users.email = seed_balances.email
JOIN assets
    ON assets.symbol = seed_balances.symbol
ON CONFLICT (user_id, asset_id) DO UPDATE
SET
    available_balance = EXCLUDED.available_balance,
    locked_balance = 0,
    updated_at = clock_timestamp();

WITH seed_balances (email, symbol, available_balance) AS (
    VALUES
        ('alice.seed@example.com', 'BTC', 0.2500000000::NUMERIC(28,10)),
        ('alice.seed@example.com', 'ETH', 4.0000000000::NUMERIC(28,10)),
        ('alice.seed@example.com', 'SOL', 300.0000000000::NUMERIC(28,10)),
        ('alice.seed@example.com', 'USDT', 250000.0000000000::NUMERIC(28,10)),
        ('alice.seed@example.com', 'BRL', 50000.0000000000::NUMERIC(28,10)),

        ('bruno.seed@example.com', 'BTC', 0.1800000000::NUMERIC(28,10)),
        ('bruno.seed@example.com', 'ETH', 3.5000000000::NUMERIC(28,10)),
        ('bruno.seed@example.com', 'SOL', 250.0000000000::NUMERIC(28,10)),
        ('bruno.seed@example.com', 'USDT', 180000.0000000000::NUMERIC(28,10)),
        ('bruno.seed@example.com', 'BRL', 35000.0000000000::NUMERIC(28,10)),

        ('carla.seed@example.com', 'BTC', 0.1200000000::NUMERIC(28,10)),
        ('carla.seed@example.com', 'ETH', 2.8000000000::NUMERIC(28,10)),
        ('carla.seed@example.com', 'SOL', 220.0000000000::NUMERIC(28,10)),
        ('carla.seed@example.com', 'USDT', 150000.0000000000::NUMERIC(28,10)),
        ('carla.seed@example.com', 'BRL', 30000.0000000000::NUMERIC(28,10)),

        ('diego.seed@example.com', 'BTC', 0.1000000000::NUMERIC(28,10)),
        ('diego.seed@example.com', 'ETH', 2.0000000000::NUMERIC(28,10)),
        ('diego.seed@example.com', 'SOL', 180.0000000000::NUMERIC(28,10)),
        ('diego.seed@example.com', 'USDT', 120000.0000000000::NUMERIC(28,10)),
        ('diego.seed@example.com', 'BRL', 25000.0000000000::NUMERIC(28,10)),

        ('eduarda.seed@example.com', 'BTC', 0.0800000000::NUMERIC(28,10)),
        ('eduarda.seed@example.com', 'ETH', 1.5000000000::NUMERIC(28,10)),
        ('eduarda.seed@example.com', 'SOL', 150.0000000000::NUMERIC(28,10)),
        ('eduarda.seed@example.com', 'USDT', 90000.0000000000::NUMERIC(28,10)),
        ('eduarda.seed@example.com', 'BRL', 20000.0000000000::NUMERIC(28,10)),

        ('felipe.seed@example.com', 'BTC', 1.5000000000::NUMERIC(28,10)),
        ('felipe.seed@example.com', 'ETH', 18.0000000000::NUMERIC(28,10)),
        ('felipe.seed@example.com', 'SOL', 1200.0000000000::NUMERIC(28,10)),
        ('felipe.seed@example.com', 'USDT', 50000.0000000000::NUMERIC(28,10)),
        ('felipe.seed@example.com', 'BRL', 18000.0000000000::NUMERIC(28,10)),

        ('gabriela.seed@example.com', 'BTC', 1.2000000000::NUMERIC(28,10)),
        ('gabriela.seed@example.com', 'ETH', 14.0000000000::NUMERIC(28,10)),
        ('gabriela.seed@example.com', 'SOL', 1000.0000000000::NUMERIC(28,10)),
        ('gabriela.seed@example.com', 'USDT', 45000.0000000000::NUMERIC(28,10)),
        ('gabriela.seed@example.com', 'BRL', 16000.0000000000::NUMERIC(28,10)),

        ('henrique.seed@example.com', 'BTC', 0.9500000000::NUMERIC(28,10)),
        ('henrique.seed@example.com', 'ETH', 11.0000000000::NUMERIC(28,10)),
        ('henrique.seed@example.com', 'SOL', 850.0000000000::NUMERIC(28,10)),
        ('henrique.seed@example.com', 'USDT', 40000.0000000000::NUMERIC(28,10)),
        ('henrique.seed@example.com', 'BRL', 14000.0000000000::NUMERIC(28,10)),

        ('isabela.seed@example.com', 'BTC', 0.7000000000::NUMERIC(28,10)),
        ('isabela.seed@example.com', 'ETH', 8.0000000000::NUMERIC(28,10)),
        ('isabela.seed@example.com', 'SOL', 650.0000000000::NUMERIC(28,10)),
        ('isabela.seed@example.com', 'USDT', 35000.0000000000::NUMERIC(28,10)),
        ('isabela.seed@example.com', 'BRL', 12000.0000000000::NUMERIC(28,10)),

        ('joao.seed@example.com', 'BTC', 0.5500000000::NUMERIC(28,10)),
        ('joao.seed@example.com', 'ETH', 6.5000000000::NUMERIC(28,10)),
        ('joao.seed@example.com', 'SOL', 500.0000000000::NUMERIC(28,10)),
        ('joao.seed@example.com', 'USDT', 30000.0000000000::NUMERIC(28,10)),
        ('joao.seed@example.com', 'BRL', 10000.0000000000::NUMERIC(28,10))
)
INSERT INTO wallet_movements (
    wallet_id,
    user_id,
    asset_id,
    movement_type,
    amount,
    available_balance_after,
    locked_balance_after,
    description
)
SELECT
    wallets.wallet_id,
    wallets.user_id,
    wallets.asset_id,
    'DEPOSIT'::enum_wallet_movement_type,
    seed_balances.available_balance,
    seed_balances.available_balance,
    0::NUMERIC(28,10),
    'Initial seed deposit'
FROM seed_balances
JOIN users
    ON users.email = seed_balances.email
JOIN assets
    ON assets.symbol = seed_balances.symbol
JOIN wallets
    ON wallets.user_id = users.user_id
   AND wallets.asset_id = assets.asset_id
WHERE seed_balances.available_balance > 0
  AND NOT EXISTS (
      SELECT 1
      FROM wallet_movements existing
      WHERE existing.wallet_id = wallets.wallet_id
        AND existing.movement_type = 'DEPOSIT'
        AND existing.description = 'Initial seed deposit'
  );
