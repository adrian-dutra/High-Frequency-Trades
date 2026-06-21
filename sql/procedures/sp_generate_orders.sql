-- Gerador de carga server-side.
-- Move o loop de geracao de ordens para dentro do banco: em vez de 3 round-trips
-- por ordem (SAVEPOINT / CALL / RELEASE), o worker Python faz UMA chamada por lote.
-- O matching continua acontecendo no banco via trigger AFTER INSERT em orders.
--
-- Cada iteracao roda dentro de um bloco BEGIN/EXCEPTION (subtransacao), que substitui
-- os SAVEPOINTs do loader: ordens que falham (ex.: saldo insuficiente) sao contadas e
-- ignoradas sem abortar o lote. O COMMIT periodico mantem os lotes pequenos.
CREATE OR REPLACE PROCEDURE sp_generate_orders(
    IN    p_order_count  INTEGER,
    IN    p_seed         DOUBLE PRECISION,
    IN    p_commit_every INTEGER DEFAULT 1000,
    INOUT p_placed       BIGINT DEFAULT 0,
    INOUT p_failed       BIGINT DEFAULT 0
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_users   BIGINT[];
    v_symbols TEXT[];
    v_refs    NUMERIC(28,10)[];
    v_qmins   NUMERIC(28,10)[];
    v_qmaxs   NUMERIC(28,10)[];
    v_ticks   NUMERIC(28,10)[];
    v_steps   NUMERIC(28,10)[];

    v_n_users   INTEGER;
    v_n_markets INTEGER;

    v_user   BIGINT;
    v_k      INTEGER;
    v_symbol TEXT;
    v_spread NUMERIC(28,10);
    v_price  NUMERIC(28,10);
    v_factor NUMERIC(28,10);
    v_qty    NUMERIC(28,10);
    v_side   enum_order_side;
    v_oid    BIGINT;
    i        INTEGER;
    v_attempt INTEGER;
BEGIN
    PERFORM setseed(p_seed);

    SELECT array_agg(user_id ORDER BY user_id)
    INTO v_users
    FROM users
    WHERE is_active = true;

    IF v_users IS NULL THEN
        RAISE EXCEPTION 'Nenhum usuario ativo encontrado. Aplique o seed antes do loader.';
    END IF;

    -- Precos de referencia e faixas de quantidade por mercado (espelham o loader
    -- antigo). Tick e step vem direto da tabela markets, mantendo as ordens validas.
    WITH m AS (
        SELECT
            symbol,
            price_tick,
            quantity_step,
            CASE symbol
                WHEN 'BTC/USDT' THEN 60000
                WHEN 'ETH/USDT' THEN 3000
                WHEN 'SOL/USDT' THEN 150
                ELSE 100
            END::NUMERIC(28,10) AS ref,
            CASE symbol
                WHEN 'BTC/USDT' THEN 0.0010
                WHEN 'ETH/USDT' THEN 0.0100
                WHEN 'SOL/USDT' THEN 0.5000
                ELSE 0.0100
            END::NUMERIC(28,10) AS qmin,
            CASE symbol
                WHEN 'BTC/USDT' THEN 0.0200
                WHEN 'ETH/USDT' THEN 0.2000
                WHEN 'SOL/USDT' THEN 10.0000
                ELSE 1.0000
            END::NUMERIC(28,10) AS qmax
        FROM markets
        WHERE is_active = true
          AND symbol IN ('BTC/USDT', 'ETH/USDT', 'SOL/USDT')
    )
    SELECT
        array_agg(symbol        ORDER BY symbol),
        array_agg(ref           ORDER BY symbol),
        array_agg(qmin          ORDER BY symbol),
        array_agg(qmax          ORDER BY symbol),
        array_agg(price_tick    ORDER BY symbol),
        array_agg(quantity_step ORDER BY symbol)
    INTO v_symbols, v_refs, v_qmins, v_qmaxs, v_ticks, v_steps
    FROM m;

    IF v_symbols IS NULL THEN
        RAISE EXCEPTION 'Nenhum mercado suportado encontrado. Aplique o seed antes do loader.';
    END IF;

    v_n_users   := array_length(v_users, 1);
    v_n_markets := array_length(v_symbols, 1);

    p_placed := 0;
    p_failed := 0;

    FOR i IN 1..p_order_count LOOP
        v_user   := v_users[1 + floor(random() * v_n_users)::INTEGER];
        v_k      := 1 + floor(random() * v_n_markets)::INTEGER;
        v_symbol := v_symbols[v_k];

        -- preco = referencia * spread(+/-0.5%), truncado ao tick do mercado
        v_spread := (0.995 + random() * 0.010)::NUMERIC(28,10);
        v_price  := trunc((v_refs[v_k] * v_spread) / v_ticks[v_k]) * v_ticks[v_k];
        IF v_price <= 0 THEN
            v_price := v_ticks[v_k];
        END IF;

        -- quantidade uniforme na faixa do mercado, truncada ao step
        v_factor := (v_qmins[v_k] + random()::NUMERIC(28,10) * (v_qmaxs[v_k] - v_qmins[v_k]));
        v_qty    := GREATEST(trunc(v_factor / v_steps[v_k]) * v_steps[v_k], v_steps[v_k]);

        v_side := CASE WHEN random() < 0.5 THEN 'BUY'::enum_order_side ELSE 'SELL'::enum_order_side END;

        -- Deadlocks sao esperados sob alta concorrencia (a ordem que casa trava as
        -- carteiras dos dois lados). Em vez de descartar a ordem, repetimos algumas
        -- vezes; a vitima do deadlock e' refeita assim que o lock e' liberado.
        v_attempt := 0;
        LOOP
            BEGIN
                CALL sp_place_order(v_user, v_symbol, v_side, v_price, v_qty, v_oid);
                p_placed := p_placed + 1;
                EXIT;
            EXCEPTION
                WHEN deadlock_detected THEN
                    v_attempt := v_attempt + 1;
                    IF v_attempt >= 10 THEN
                        p_failed := p_failed + 1;
                        EXIT;
                    END IF;
                WHEN OTHERS THEN
                    p_failed := p_failed + 1;
                    EXIT;
            END;
        END LOOP;

        IF p_commit_every > 0 AND (i % p_commit_every = 0) THEN
            COMMIT;
        END IF;
    END LOOP;

    COMMIT;
END;
$$;
