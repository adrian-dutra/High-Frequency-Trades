import argparse
import csv
import io
import os
import random
import sys
import time
from collections import Counter
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_DOWN

import psycopg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import load_config


REFERENCE_PRICES = {
    "BTC/USDT": Decimal("60000.00"),
    "ETH/USDT": Decimal("3000.00"),
    "SOL/USDT": Decimal("150.00"),
}

QUANTITY_RANGES = {
    "BTC/USDT": (Decimal("0.0010"), Decimal("0.0200")),
    "ETH/USDT": (Decimal("0.0100"), Decimal("0.2000")),
    "SOL/USDT": (Decimal("0.5000"), Decimal("10.0000")),
}

WARMUP_TARGETS = {
    "USDT": Decimal("50000000.0000000000"),
    "BTC": Decimal("500.0000000000"),
    "ETH": Decimal("5000.0000000000"),
    "SOL": Decimal("200000.0000000000"),
    "BRL": Decimal("5000000.0000000000"),
}

PRICE_STEP = Decimal("0.01")
QUANTITY_STEP = Decimal("0.0001")
CANDLE_BATCH_ROWS = 100_000
MIN_USERS = 100


def quantize(value, step):
    return value.quantize(step, rounding=ROUND_DOWN)


def parse_date(value):
    parsed = datetime.strptime(value, "%Y-%m-%d")
    return parsed.replace(tzinfo=timezone.utc)


def split_counts(total, workers):
    base = total // workers
    counts = [base] * workers
    for index in range(total - base * workers):
        counts[index] += 1
    return counts


def format_size(size_bytes):
    units = ["bytes", "kB", "MB", "GB"]
    value = float(size_bytes)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.2f} {unit}" if unit != "bytes" else f"{int(value)} bytes"
        value /= 1024
    return f"{value:.2f} GB"


def collect_metrics(conninfo):
    metrics = {}
    with psycopg.connect(conninfo) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM users")
            metrics["users"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM markets")
            metrics["markets"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM orders")
            metrics["orders"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM trades")
            metrics["trades"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM candles_1m")
            metrics["candles_1m"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM wallet_movements")
            metrics["wallet_movements"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM order_audit_log")
            metrics["order_audit_log"] = cur.fetchone()[0]
            cur.execute("SELECT COALESCE(SUM(quote_amount), 0) FROM trades")
            metrics["traded_volume_quote"] = cur.fetchone()[0]
            cur.execute("SELECT pg_database_size(current_database())")
            metrics["database_size_bytes"] = cur.fetchone()[0]
    metrics["database_size"] = format_size(metrics["database_size_bytes"])
    return metrics


def print_metrics(metrics, elapsed):
    print("=== Resumo do banco ===")
    print(f"Tamanho do banco: {metrics['database_size']}")
    print(f"Users: {metrics['users']}")
    print(f"Markets: {metrics['markets']}")
    print(f"Orders: {metrics['orders']}")
    print(f"Trades: {metrics['trades']}")
    print(f"Candles 1m: {metrics['candles_1m']}")
    print(f"Wallet movements: {metrics['wallet_movements']}")
    print(f"Order audit log: {metrics['order_audit_log']}")
    print(f"Volume negociado (quote): {metrics['traded_volume_quote']}")
    print(f"Tempo total: {elapsed:.2f} s")


def fetch_active_users(conninfo):
    with psycopg.connect(conninfo) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT user_id FROM users WHERE is_active = true ORDER BY user_id")
            return [row[0] for row in cur.fetchall()]


def fetch_realtime_markets(conninfo):
    with psycopg.connect(conninfo) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT symbol FROM markets WHERE is_active = true ORDER BY market_id")
            markets = [row[0] for row in cur.fetchall()]
    return [market for market in markets if market in REFERENCE_PRICES]


def ensure_users(cur, min_users):
    values = [
        (f"Loader User {index:03d}", f"loader{index:03d}@example.com", True)
        for index in range(1, min_users + 1)
    ]
    cur.executemany(
        """
        INSERT INTO users (name, email, is_active)
        VALUES (%s, %s, %s)
        ON CONFLICT (email) DO UPDATE
        SET name = EXCLUDED.name,
            is_active = EXCLUDED.is_active
        """,
        values,
    )


def ensure_synthetic_markets(conninfo, candle_markets):
    with psycopg.connect(conninfo) as conn:
        conn.autocommit = False
        with conn.cursor() as cur:
            cur.execute("SELECT asset_id FROM assets WHERE symbol = 'USDT'")
            row = cur.fetchone()
            if row is None:
                raise RuntimeError("Asset USDT nao encontrado. Aplique a seed antes do loader.")
            usdt_asset_id = row[0]

            cur.execute("SELECT symbol FROM markets WHERE is_active = true")
            active_market_symbols = {row[0] for row in cur.fetchall()}

            if len(active_market_symbols) >= candle_markets:
                conn.commit()
                return

            created = 0
            index = 1
            while len(active_market_symbols) < candle_markets:
                symbol = f"LD{index:03d}"
                market_symbol = f"{symbol}/USDT"
                index += 1

                if market_symbol in active_market_symbols:
                    continue

                cur.execute(
                    """
                    INSERT INTO assets (symbol, name, decimal_places, is_active)
                    VALUES (%s, %s, 8, true)
                    ON CONFLICT (symbol) DO UPDATE
                    SET name = EXCLUDED.name,
                        decimal_places = EXCLUDED.decimal_places,
                        is_active = EXCLUDED.is_active
                    RETURNING asset_id
                    """,
                    (symbol, f"Loader Asset {symbol}"),
                )
                base_asset_id = cur.fetchone()[0]
                cur.execute(
                    """
                    INSERT INTO markets (
                        base_asset_id,
                        quote_asset_id,
                        symbol,
                        min_order_quantity,
                        price_tick,
                        quantity_step,
                        is_active
                    )
                    VALUES (%s, %s, %s, 0.0001000000, 0.0100000000, 0.0001000000, true)
                    ON CONFLICT (symbol) DO UPDATE
                    SET base_asset_id = EXCLUDED.base_asset_id,
                        quote_asset_id = EXCLUDED.quote_asset_id,
                        min_order_quantity = EXCLUDED.min_order_quantity,
                        price_tick = EXCLUDED.price_tick,
                        quantity_step = EXCLUDED.quantity_step,
                        is_active = EXCLUDED.is_active
                    """,
                    (base_asset_id, usdt_asset_id, market_symbol),
                )
                active_market_symbols.add(market_symbol)
                created += 1
        conn.commit()
    print(f"Markets sinteticos garantidos: {created}")


def ensure_wallets_for_all_assets(cur):
    cur.execute(
        """
        INSERT INTO wallets (user_id, asset_id, available_balance, locked_balance)
        SELECT u.user_id, a.asset_id, 0, 0
        FROM users u
        CROSS JOIN assets a
        WHERE u.is_active = true
          AND a.is_active = true
        ON CONFLICT (user_id, asset_id) DO NOTHING
        """
    )


def warmup(conninfo, min_users=MIN_USERS):
    print("=== Fase warmup ===")
    start = time.perf_counter()
    deposits = 0

    with psycopg.connect(conninfo) as conn:
        conn.autocommit = False
        with conn.cursor() as cur:
            ensure_users(cur, min_users)
            ensure_wallets_for_all_assets(cur)
            cur.execute(
                """
                SELECT w.user_id, a.symbol, w.available_balance
                FROM wallets w
                JOIN assets a ON a.asset_id = w.asset_id
                JOIN users u ON u.user_id = w.user_id
                WHERE u.is_active = true
                  AND a.is_active = true
                ORDER BY w.user_id, a.symbol
                """
            )
            rows = cur.fetchall()

            for user_id, symbol, available in rows:
                target = WARMUP_TARGETS.get(symbol, Decimal("1000000.0000000000"))
                if available >= target:
                    continue
                amount = target - available
                cur.execute("SAVEPOINT dep")
                try:
                    cur.execute(
                        "CALL sp_deposit(%s, %s, %s, %s)",
                        (user_id, symbol, amount, "Warmup loader"),
                    )
                    cur.execute("RELEASE SAVEPOINT dep")
                    deposits += 1
                except psycopg.Error:
                    cur.execute("ROLLBACK TO SAVEPOINT dep")
                    cur.execute("RELEASE SAVEPOINT dep")
            conn.commit()

    elapsed = time.perf_counter() - start
    print(f"Depositos executados: {deposits}")
    print(f"Tempo warmup: {elapsed:.2f} s")
    return {"deposits": deposits, "elapsed": elapsed}


def build_coordinated_order(markets, index):
    market = markets[index % len(markets)]
    reference = REFERENCE_PRICES[market]
    qmin, qmax = QUANTITY_RANGES[market]
    quantity_factor = Decimal(str(random.uniform(float(qmin), float(qmax))))
    quantity = quantize(quantity_factor, QUANTITY_STEP)
    if quantity < QUANTITY_STEP:
        quantity = QUANTITY_STEP

    if index % 2 == 0:
        side = "SELL"
        price = quantize(reference * Decimal("0.999"), PRICE_STEP)
    else:
        side = "BUY"
        price = quantize(reference * Decimal("1.001"), PRICE_STEP)

    return market, side, price, quantity


def normalize_db_error(error):
    message = str(error).strip().splitlines()
    if not message:
        return error.__class__.__name__
    return message[0][:240]


def run_order_worker(args):
    worker_id, conninfo, users, markets, order_count, batch_size, seed = args
    random.seed(seed)
    placed = 0
    failed = 0
    errors = Counter()
    start = time.perf_counter()

    if len(users) < 2:
        elapsed = time.perf_counter() - start
        return {
            "worker_id": worker_id,
            "placed": placed,
            "failed": order_count,
            "elapsed": elapsed,
            "orders_per_second": 0,
            "avg_seconds_per_order": 0,
            "errors": {"worker sem usuarios suficientes": order_count},
        }

    seller_users = users[::2] or users
    buyer_users = users[1::2] or users

    with psycopg.connect(conninfo) as conn:
        conn.autocommit = False
        with conn.cursor() as cur:
            for index in range(order_count):
                market, side, price, quantity = build_coordinated_order(markets, index)
                user_pool = seller_users if side == "SELL" else buyer_users
                user_id = user_pool[index % len(user_pool)]

                if batch_size <= 1:
                    try:
                        cur.execute(
                            "CALL sp_place_order(%s, %s, %s, %s, %s, NULL)",
                            (user_id, market, side, price, quantity),
                        )
                        conn.commit()
                        placed += 1
                    except psycopg.Error as error:
                        conn.rollback()
                        errors[normalize_db_error(error)] += 1
                        failed += 1
                    continue

                cur.execute("SAVEPOINT ord")
                try:
                    cur.execute(
                        "CALL sp_place_order(%s, %s, %s, %s, %s, NULL)",
                        (user_id, market, side, price, quantity),
                    )
                    cur.execute("RELEASE SAVEPOINT ord")
                    placed += 1
                except psycopg.Error as error:
                    cur.execute("ROLLBACK TO SAVEPOINT ord")
                    cur.execute("RELEASE SAVEPOINT ord")
                    errors[normalize_db_error(error)] += 1
                    failed += 1

                if (index + 1) % batch_size == 0:
                    conn.commit()
            if batch_size > 1:
                conn.commit()

    elapsed = time.perf_counter() - start
    attempted = placed + failed
    return {
        "worker_id": worker_id,
        "placed": placed,
        "failed": failed,
        "elapsed": elapsed,
        "orders_per_second": placed / elapsed if elapsed > 0 else 0,
        "avg_seconds_per_order": elapsed / attempted if attempted > 0 else 0,
        "errors": dict(errors),
    }


def partition_users(users, workers):
    shards = [[] for _ in range(workers)]
    for index, user_id in enumerate(users):
        shards[index % workers].append(user_id)
    return shards


def run_real_orders(conninfo, total_orders, workers, batch_size):
    print("=== Fase real-orders ===")
    start_trades = collect_metrics(conninfo)["trades"]
    users = fetch_active_users(conninfo)
    markets = fetch_realtime_markets(conninfo)

    if not users:
        raise RuntimeError("Nenhum usuario ativo encontrado. Execute warmup ou seed antes.")
    if not markets:
        raise RuntimeError("Nenhum mercado BTC/USDT, ETH/USDT ou SOL/USDT ativo encontrado.")

    workers = max(4, workers)
    user_shards = partition_users(users, workers)
    counts = split_counts(total_orders, workers)
    tasks = [
        (
            index + 1,
            conninfo,
            user_shards[index],
            markets,
            counts[index],
            batch_size,
            1000 + index,
        )
        for index in range(workers)
    ]

    start = time.perf_counter()
    placed = 0
    failed = 0
    worker_results = []
    all_errors = Counter()
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(run_order_worker, task) for task in tasks]
        for future in as_completed(futures):
            worker_result = future.result()
            worker_results.append(worker_result)
            placed += worker_result["placed"]
            failed += worker_result["failed"]
            all_errors.update(worker_result["errors"])
    elapsed = time.perf_counter() - start
    end_trades = collect_metrics(conninfo)["trades"]

    print(f"Workers: {workers}")
    print(f"Ordens alvo: {total_orders}")
    print(f"Ordens criadas: {placed}")
    print(f"Ordens com falha: {failed}")
    print(f"Trades gerados nesta fase: {end_trades - start_trades}")
    print(f"Tempo real-orders: {elapsed:.2f} s")
    if elapsed > 0:
        print(f"Throughput real-orders: {placed / elapsed:.1f} ordens/s")
    print("Metricas por worker:")
    for worker_result in sorted(worker_results, key=lambda item: item["worker_id"]):
        print(
            "  "
            f"worker={worker_result['worker_id']} "
            f"criadas={worker_result['placed']} "
            f"falhas={worker_result['failed']} "
            f"tempo={worker_result['elapsed']:.2f}s "
            f"ordens/s={worker_result['orders_per_second']:.2f} "
            f"media_por_ordem={worker_result['avg_seconds_per_order']:.4f}s"
        )
    if all_errors:
        print("Top 5 erros real-orders:")
        for message, count in all_errors.most_common(5):
            print(f"  {count}x {message}")
    else:
        print("Top 5 erros real-orders: nenhum erro registrado")

    return {
        "placed": placed,
        "failed": failed,
        "trades_generated": end_trades - start_trades,
        "elapsed": elapsed,
        "worker_results": worker_results,
        "top_errors": dict(all_errors.most_common(5)),
    }


def fetch_candle_markets(conninfo, candle_markets):
    with psycopg.connect(conninfo) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT market_id, symbol
                FROM markets
                WHERE is_active = true
                ORDER BY market_id
                LIMIT %s
                """,
                (candle_markets,),
            )
            return cur.fetchall()


def candle_reference_price(symbol):
    if symbol in REFERENCE_PRICES:
        return REFERENCE_PRICES[symbol]
    if symbol.startswith("LD"):
        number = int(symbol[2:5])
        return Decimal("10.00") + Decimal(number)
    return Decimal("100.00")


def create_temp_candles_table(cur):
    cur.execute(
        """
        CREATE TEMP TABLE tmp_loader_candles (
            market_id INTEGER NOT NULL,
            bucket_minute TIMESTAMPTZ NOT NULL,
            open_price NUMERIC(28,10) NOT NULL,
            high_price NUMERIC(28,10) NOT NULL,
            low_price NUMERIC(28,10) NOT NULL,
            close_price NUMERIC(28,10) NOT NULL,
            volume_base NUMERIC(28,10) NOT NULL,
            volume_quote NUMERIC(28,10) NOT NULL,
            trades_count INTEGER NOT NULL
        ) ON COMMIT DROP
        """
    )


def copy_candles(cur, rows):
    output = io.StringIO()
    writer = csv.writer(output)
    for row in rows:
        writer.writerow(row)
    output.seek(0)
    with cur.copy(
        """
        COPY tmp_loader_candles (
            market_id,
            bucket_minute,
            open_price,
            high_price,
            low_price,
            close_price,
            volume_base,
            volume_quote,
            trades_count
        )
        FROM STDIN WITH (FORMAT CSV)
        """
    ) as copy:
        copy.write(output.read())


def insert_candles_from_temp(cur):
    cur.execute(
        """
        INSERT INTO candles_1m (
            market_id,
            bucket_minute,
            open_price,
            high_price,
            low_price,
            close_price,
            volume_base,
            volume_quote,
            trades_count
        )
        SELECT
            market_id,
            bucket_minute,
            open_price,
            high_price,
            low_price,
            close_price,
            volume_base,
            volume_quote,
            trades_count
        FROM tmp_loader_candles
        ON CONFLICT (market_id, bucket_minute) DO NOTHING
        """
    )
    return cur.rowcount


def build_candle_row(market_id, symbol, bucket_minute, sequence):
    reference = candle_reference_price(symbol)
    wave = Decimal(sequence % 100) / Decimal("10000")
    open_price = quantize(reference * (Decimal("1.0000") + wave), PRICE_STEP)
    high_price = quantize(open_price * Decimal("1.0020"), PRICE_STEP)
    low_price = quantize(open_price * Decimal("0.9980"), PRICE_STEP)
    close_price = quantize(reference * (Decimal("1.0005") + wave), PRICE_STEP)
    volume_base = quantize(Decimal("1.0000") + Decimal(sequence % 50), QUANTITY_STEP)
    volume_quote = quantize(volume_base * close_price, PRICE_STEP)
    trades_count = 1 + (sequence % 25)

    return (
        market_id,
        bucket_minute.isoformat(),
        open_price,
        high_price,
        low_price,
        close_price,
        volume_base,
        volume_quote,
        trades_count,
    )


def run_bulk_candles(conninfo, target_db_mb, candle_markets, start_date, end_date):
    print("=== Fase bulk-candles ===")
    start = time.perf_counter()
    target_bytes = target_db_mb * 1024 * 1024
    start_dt = parse_date(start_date)
    end_dt = parse_date(end_date)

    if start_dt < datetime(2026, 1, 1, tzinfo=timezone.utc):
        raise RuntimeError("start-date deve estar dentro de 2026.")
    if end_dt > datetime(2027, 1, 1, tzinfo=timezone.utc):
        raise RuntimeError("end-date deve estar dentro das particoes de 2026.")
    if start_dt >= end_dt:
        raise RuntimeError("start-date deve ser anterior a end-date.")

    ensure_synthetic_markets(conninfo, candle_markets)
    markets = fetch_candle_markets(conninfo, candle_markets)
    if not markets:
        raise RuntimeError("Nenhum market ativo disponivel para gerar candles.")

    inserted_total = 0
    sequence = 0
    bucket_minute = start_dt
    metrics = collect_metrics(conninfo)

    while metrics["database_size_bytes"] < target_bytes and bucket_minute < end_dt:
        rows = []
        while len(rows) < CANDLE_BATCH_ROWS and bucket_minute < end_dt:
            for market_id, symbol in markets:
                rows.append(build_candle_row(market_id, symbol, bucket_minute, sequence))
                sequence += 1
                if len(rows) >= CANDLE_BATCH_ROWS:
                    break
            bucket_minute += timedelta(minutes=1)

        if not rows:
            break

        with psycopg.connect(conninfo) as conn:
            conn.autocommit = False
            with conn.cursor() as cur:
                create_temp_candles_table(cur)
                copy_candles(cur, rows)
                inserted = insert_candles_from_temp(cur)
            conn.commit()

        inserted_total += inserted
        metrics = collect_metrics(conninfo)
        print(
            "Candles inseridos no lote: "
            f"{inserted}; total fase: {inserted_total}; "
            f"tamanho: {metrics['database_size']}"
        )

    elapsed = time.perf_counter() - start
    print(f"Tempo bulk-candles: {elapsed:.2f} s")
    return {"inserted": inserted_total, "elapsed": elapsed}


def parse_args(default_config):
    parser = argparse.ArgumentParser(description="Loader hibrido do HFT Simulator.")
    parser.add_argument(
        "--mode",
        choices=["warmup", "real-orders", "bulk-candles", "full"],
        default=default_config.mode,
    )
    parser.add_argument("--target-db-mb", type=int, default=default_config.target_db_mb)
    parser.add_argument("--real-orders", type=int, default=default_config.real_orders)
    parser.add_argument("--workers", type=int, default=default_config.workers)
    parser.add_argument("--batch-size", type=int, default=default_config.batch_size)
    parser.add_argument("--candle-markets", type=int, default=default_config.candle_markets)
    parser.add_argument("--start-date", default=default_config.start_date)
    parser.add_argument("--end-date", default=default_config.end_date)
    return parser.parse_args()


def main():
    default_config = load_config()
    args = parse_args(default_config)
    config = replace(
        default_config,
        mode=args.mode,
        target_db_mb=args.target_db_mb,
        real_orders=args.real_orders,
        workers=max(4, args.workers),
        batch_size=args.batch_size,
        candle_markets=args.candle_markets,
        start_date=args.start_date,
        end_date=args.end_date,
    )

    start = time.perf_counter()

    if config.mode in ("warmup", "full"):
        if config.mode == "full":
            ensure_synthetic_markets(config.conninfo, config.candle_markets)
        warmup(config.conninfo, MIN_USERS)

    if config.mode in ("real-orders", "full"):
        run_real_orders(
            config.conninfo,
            config.real_orders,
            config.workers,
            config.batch_size,
        )

    if config.mode in ("bulk-candles", "full"):
        run_bulk_candles(
            config.conninfo,
            config.target_db_mb,
            config.candle_markets,
            config.start_date,
            config.end_date,
        )

    elapsed = time.perf_counter() - start
    print_metrics(collect_metrics(config.conninfo), elapsed)


if __name__ == "__main__":
    main()