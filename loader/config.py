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
    workers: int = field(default_factory=lambda: max(4, int(os.getenv("LOADER_WORKERS", "4"))))
    target_orders: int = field(default_factory=lambda: int(os.getenv("LOADER_TARGET_ORDERS", "100000")))
    batch_size: int = field(default_factory=lambda: int(os.getenv("LOADER_BATCH_SIZE", "200")))
    seed_users: int = field(default_factory=lambda: int(os.getenv("LOADER_SEED_USERS", "0")))

    @property
    def conninfo(self) -> str:
        return (
            f"host={self.host} port={self.port} dbname={self.dbname} "
            f"user={self.user} password={self.password}"
        )


def load_config() -> LoaderConfig:
    return LoaderConfig()
