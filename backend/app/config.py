from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "知进伴学"
    public_base_url: str = "https://xue.evowit.com"
    data_dir: Path = Path("data")
    llm_base_url: str = "http://100.64.0.5:39000/v1"
    llm_api_key: str = "ollama"
    llm_model: str = "evowit-agent27b"
    max_upload_mb: int = 20

    model_config = SettingsConfigDict(env_prefix="XUE_")


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    (settings.data_dir / "images").mkdir(parents=True, exist_ok=True)
    return settings

