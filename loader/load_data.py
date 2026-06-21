import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from decimal import Decimal

import psycopg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import load_config


SUPPORTED_MARKETS = ("BTC/USDT", "ETH/USDT", "SOL/USDT")

# Saldo inicial generoso por ativo. Mais usuarios = menos disputa de lock entre os
# workers (cada ordem trava a carteira do dono via FOR UPDATE), entao o gargalo de
# concorrencia some quando ha muitos usuarios disponiveis.
SEED_BALANCES = {
    "USDT": Decimal("50000000"),
    "BTC": Decimal("500"),
    "ETH": Decimal("5000"),
    "SOL": Decimal("200000"),
}


def tune_session(cur):
    # Gerador de carga descartavel: nao precisamos esperar o fsync do WAL a cada
    # commit, nem receber os NOTICE emitidos pelas procedures (puro overhead aqui).
    cur.execute("SET synchronous_commit = OFF")
    cur.execute("SET client_min_messages = WARNING")
    # Sob concorrencia o matching gera deadlocks (cada ordem casada trava as carteiras
    # dos dois lados). Detectar rapido + repetir (na sp_generate_orders) recupera em ms
    # em vez do 1s padrao, mantendo a vazao alta.
    cur.execute("SET deadlock_timeout = '10ms'")


def seed_load_users(conninfo, n_users):
    # Cria usuarios sinteticos em massa (uma instrucao so, sem round-trip por usuario).
    if n_users <= 0:
        return
    with psycopg.connect(conninfo, autocommit=True) as conn:
        with conn.cursor() as cur:
            tune_session(cur)
            cur.execute(
                """
                INSERT INTO users (name, email, is_active)
                SELECT 'Loader User ' || g,
                       'loader_' || g || '@example.com',
                       true
                FROM generate_series(1, %s) AS g
                ON CONFLICT (email) DO NOTHING
                """,
                (n_users,),
            )


def ensure_balances(conninfo):
    # Garante carteira com saldo alto para TODOS os usuarios ativos, set-based.
    with psycopg.connect(conninfo, autocommit=True) as conn:
        with conn.cursor() as cur:
            tune_session(cur)
            for symbol, amount in SEED_BALANCES.items():
                cur.execute(
                    """
                    INSERT INTO wallets (user_id, asset_id, available_balance, locked_balance)
                    SELECT u.user_id, a.asset_id, %s, 0
                    FROM users u
                    CROSS JOIN assets a
                    WHERE u.is_active = true
                      AND a.symbol = %s
                    ON CONFLICT (user_id, asset_id) DO UPDATE
                    SET available_balance = GREATEST(wallets.available_balance, EXCLUDED.available_balance)
                    """,
                    (amount, symbol),
                )


def fetch_targets(conninfo):
    with psycopg.connect(conninfo) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM users WHERE is_active = true")
            users = cur.fetchone()[0]
            cur.execute("SELECT symbol FROM markets WHERE is_active = true ORDER BY market_id")
            markets = [row[0] for row in cur.fetchall()]
    markets = [m for m in markets if m in SUPPORTED_MARKETS]
    return users, markets


def run_worker(args):
    conninfo, order_count, commit_every, seed = args
    # autocommit=True e' obrigatorio: sp_generate_orders controla a transacao
    # (COMMIT periodico), o que so e' permitido fora de um bloco transacional explicito.
    with psycopg.connect(conninfo, autocommit=True) as conn:
        with conn.cursor() as cur:
            tune_session(cur)
            cur.execute(
                "CALL sp_generate_orders(%s, %s, %s, NULL, NULL)",
                (order_count, seed, commit_every),
            )
            placed, failed = cur.fetchone()
    return int(placed), int(failed)


def split_counts(total, workers):
    base = total // workers
    counts = [base] * workers
    for i in range(total - base * workers):
        counts[i] += 1
    return counts


def collect_metrics(conninfo):
    metrics = {}
    with psycopg.connect(conninfo) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM orders")
            metrics["orders"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM trades")
            metrics["trades"] = cur.fetchone()[0]
            cur.execute("SELECT COALESCE(SUM(quote_amount), 0) FROM trades")
            metrics["traded_volume_quote"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM wallet_movements")
            metrics["wallet_movements"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM candles_1m")
            metrics["candles"] = cur.fetchone()[0]
            cur.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
            metrics["database_size"] = cur.fetchone()[0]
    return metrics


def main():
    config = load_config()
    conninfo = config.conninfo

    seed_load_users(conninfo, config.seed_users)
    ensure_balances(conninfo)

    users, markets = fetch_targets(conninfo)
    if not users:
        raise SystemExit("Nenhum usuario ativo encontrado. Aplique o seed antes do loader.")
    if not markets:
        raise SystemExit("Nenhum mercado suportado encontrado. Aplique o seed antes do loader.")

    counts = split_counts(config.target_orders, config.workers)
    # setseed() exige um valor em (-1, 1); damos uma seed distinta por worker.
    tasks = [
        (conninfo, counts[i], config.batch_size, (i + 1) / (config.workers + 1))
        for i in range(config.workers)
    ]

    start = time.perf_counter()
    placed = 0
    failed = 0
    with ProcessPoolExecutor(max_workers=config.workers) as executor:
        futures = [executor.submit(run_worker, task) for task in tasks]
        for future in as_completed(futures):
            worker_placed, worker_failed = future.result()
            placed += worker_placed
            failed += worker_failed
    elapsed = time.perf_counter() - start

    metrics = collect_metrics(conninfo)

    print("=== Loader HFT ===")
    print(f"Workers: {config.workers}")
    print(f"Ordens alvo: {config.target_orders}")
    print(f"Ordens enviadas com sucesso: {placed}")
    print(f"Ordens rejeitadas: {failed}")
    print(f"Tempo total: {elapsed:.2f} s")
    if elapsed > 0:
        print(f"Throughput: {placed / elapsed:.1f} ordens/s")
    print(f"Total de ordens no banco: {metrics['orders']}")
    print(f"Total de trades no banco: {metrics['trades']}")
    print(f"Volume negociado (quote): {metrics['traded_volume_quote']}")
    print(f"Movimentos de carteira: {metrics['wallet_movements']}")
    print(f"Candles 1m: {metrics['candles']}")
    print(f"Tamanho do banco: {metrics['database_size']}")


if __name__ == "__main__":
    main()
