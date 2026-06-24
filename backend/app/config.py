from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "知进伴学"
    public_base_url: str = "https://xue.evowit.com"
    data_dir: Path = Path("data")
    database_url: str = "sqlite:///data/xue.sqlite3"
    redis_url: str = ""
    llm_base_url: str = "http://100.64.0.5:39000/v1"
    llm_api_key: str = "ollama"
    llm_model: str = "evowit-agent27b"
    llm_provider: str = "evowit"
    llm_gateway_url: str = ""
    llm_gateway_key: str = ""
    embed_url: str = ""
    embed_dim: int = 512
    llm_max_concurrency: int = 1
    llm_min_interval_seconds: float = 8.0
    llm_queue_warn_size: int = 3
    max_upload_mb: int = 20
    control_token: str = ""
    auth_required: bool = False
    registration_enabled: bool = True
    auth_secret_key: str = ""
    auth_token_ttl_minutes: int = 43200
    default_account_id: str = "local"

    model_config = SettingsConfigDict(env_prefix="XUE_")


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    (settings.data_dir / "images").mkdir(parents=True, exist_ok=True)
    (settings.data_dir / "thumbnails").mkdir(parents=True, exist_ok=True)
    (settings.data_dir / "visualizations").mkdir(parents=True, exist_ok=True)
    return settings
