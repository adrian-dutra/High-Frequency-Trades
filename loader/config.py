import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class LoaderConfig:
    host: str = field(default_factory=lambda: os.getenv("POSTGRES_HOST", "localhost"))
    port: int = field(default_factory=lambda: int(os.getenv("POSTGRES_PORT", "5432")))
    dbname: str = field(default_factory=lambda: os.getenv("POSTGRES_DB", "hft_simulator"))
    user: str = field(default_factory=lambda: os.getenv("POSTGRES_USER", "hft_user"))
    password: str = field(default_factory=lambda: os.getenv("POSTGRES_PASSWORD", ""))
    mode: str = field(default_factory=lambda: os.getenv("LOADER_MODE", "full"))
    target_db_mb: int = field(default_factory=lambda: int(os.getenv("LOADER_TARGET_DB_MB", "700")))
    real_orders: int = field(default_factory=lambda: int(os.getenv("LOADER_REAL_ORDERS", "5000")))
    workers: int = field(default_factory=lambda: max(4, int(os.getenv("LOADER_WORKERS", "4"))))
    batch_size: int = field(default_factory=lambda: int(os.getenv("LOADER_BATCH_SIZE", "1")))
    candle_markets: int = field(default_factory=lambda: int(os.getenv("LOADER_CANDLE_MARKETS", "80")))
    start_date: str = field(default_factory=lambda: os.getenv("LOADER_START_DATE", "2026-01-01"))
    end_date: str = field(default_factory=lambda: os.getenv("LOADER_END_DATE", "2027-01-01"))

    @property
    def conninfo(self) -> str:
        return (
            f"host={self.host} port={self.port} dbname={self.dbname} "
            f"user={self.user} password={self.password}"
        )


def load_config() -> LoaderConfig:
    return LoaderConfig()
