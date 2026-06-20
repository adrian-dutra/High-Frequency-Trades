import os
import random
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from decimal import Decimal, ROUND_DOWN

import psycopg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import load_config


REFERENCE_PRICES = {
    "BTC/USDT": Decimal("60000"),
    "ETH/USDT": Decimal("3000"),
    "SOL/USDT": Decimal("150"),
}

QUANTITY_RANGES = {
    "BTC/USDT": (Decimal("0.0010"), Decimal("0.0200")),
    "ETH/USDT": (Decimal("0.0100"), Decimal("0.2000")),
    "SOL/USDT": (Decimal("0.5000"), Decimal("10.0000")),
}

WARMUP_DEPOSITS = {
    "USDT": Decimal("50000000"),
    "BTC": Decimal("500"),
    "ETH": Decimal("5000"),
    "SOL": Decimal("200000"),
}

PRICE_STEP = Decimal("0.01")
QUANTITY_STEP = Decimal("0.0001")


def quantize(value, step):
    return value.quantize(step, rounding=ROUND_DOWN)


def fetch_targets(conninfo):
    with psycopg.connect(conninfo) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT user_id FROM users WHERE is_active = true ORDER BY user_id")
            users = [row[0] for row in cur.fetchall()]
            cur.execute("SELECT symbol FROM markets WHERE is_active = true ORDER BY market_id")
            markets = [row[0] for row in cur.fetchall()]
    markets = [m for m in markets if m in REFERENCE_PRICES]
    return users, markets


def warmup(conninfo, users):
    with psycopg.connect(conninfo) as conn:
        conn.autocommit = False
        with conn.cursor() as cur:
            for user_id in users:
                for symbol, amount in WARMUP_DEPOSITS.items():
                    cur.execute(
                        "SAVEPOINT dep",
                    )
                    try:
                        cur.execute(
                            "CALL sp_deposit(%s, %s, %s, %s)",
                            (user_id, symbol, amount, "Warmup loader"),
                        )
                        cur.execute("RELEASE SAVEPOINT dep")
                    except psycopg.Error:
                        cur.execute("ROLLBACK TO SAVEPOINT dep")
                        cur.execute("RELEASE SAVEPOINT dep")
            conn.commit()


def build_order(markets):
    market = random.choice(markets)
    reference = REFERENCE_PRICES[market]
    spread = Decimal(str(random.uniform(0.995, 1.005)))
    price = quantize(reference * spread, PRICE_STEP)
    qmin, qmax = QUANTITY_RANGES[market]
    factor = Decimal(str(random.uniform(float(qmin), float(qmax))))
    quantity = quantize(factor, QUANTITY_STEP)
    if quantity < QUANTITY_STEP:
        quantity = QUANTITY_STEP
    side = "BUY" if random.random() < 0.5 else "SELL"
    return market, side, price, quantity


def run_worker(args):
    conninfo, users, markets, order_count, batch_size, seed = args
    random.seed(seed)
    placed = 0
    failed = 0
    with psycopg.connect(conninfo) as conn:
        conn.autocommit = False
        with conn.cursor() as cur:
            for i in range(order_count):
                user_id = random.choice(users)
                market, side, price, quantity = build_order(markets)
                cur.execute("SAVEPOINT ord")
                try:
                    cur.execute(
                        "CALL sp_place_order(%s, %s, %s, %s, %s, NULL)",
                        (user_id, market, side, price, quantity),
                    )
                    cur.execute("RELEASE SAVEPOINT ord")
                    placed += 1
                except psycopg.Error:
                    cur.execute("ROLLBACK TO SAVEPOINT ord")
                    cur.execute("RELEASE SAVEPOINT ord")
                    failed += 1
                if (i + 1) % batch_size == 0:
                    conn.commit()
            conn.commit()
    return placed, failed


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

    users, markets = fetch_targets(conninfo)
    if not users:
        raise SystemExit("Nenhum usuario ativo encontrado. Aplique o seed antes do loader.")
    if not markets:
        raise SystemExit("Nenhum mercado suportado encontrado. Aplique o seed antes do loader.")

    warmup(conninfo, users)

    counts = split_counts(config.target_orders, config.workers)
    tasks = [
        (conninfo, users, markets, counts[i], config.batch_size, 1000 + i)
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
