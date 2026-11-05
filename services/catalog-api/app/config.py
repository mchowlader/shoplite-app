import os
from pydantic import BaseModel

class Settings(BaseModel):
    SERVICE_NAME: str = "catalog-api"
    PORT: int = int(os.getenv("PORT", "8000"))
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")

    # PostgreSQL Database Configuration
    DB_USER: str = os.getenv("DB_USER", "postgres")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "postgres123")
    DB_HOST: str = os.getenv("DB_HOST", "localhost")
    DB_PORT: str = os.getenv("DB_PORT", "5432")
    DB_NAME: str = os.getenv("DB_NAME", "shoplite_db")

    @property
    def DATABASE_URL(self) -> str:
        return f"postgresql://{self.DB_USER}:{self.DB_PASSWORD}@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}"

    # Redis Queue Configuration (Section 1.1 specifies Redis list 'orders:pending')
    REDIS_HOST: str = os.getenv("REDIS_HOST", "localhost")
    REDIS_PORT: int = int(os.getenv("REDIS_PORT", "6379"))
    REDIS_DB: int = int(os.getenv("REDIS_DB", "0"))
    REDIS_QUEUE_NAME: str = os.getenv("REDIS_QUEUE_NAME", "orders:pending")

    # Fault-Injection Flags (Section 1.5 - Disabled by default)
    CHAOS_LATENCY_MS: int = int(os.getenv("CHAOS_LATENCY_MS", "0"))
    CHAOS_ERROR_RATE: float = float(os.getenv("CHAOS_ERROR_RATE", "0.0"))

settings = Settings()

